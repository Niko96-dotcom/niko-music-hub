import CryptoKit
import Foundation
import Security

/// The key that signs yt-dlp releases, and the check of a release's checksum list against it.
///
/// yt-dlp follows the newest release, because sites change and old builds stop working, so no hash can be pinned
/// for it. Every release signs its `SHA2-256SUMS` with an OpenPGP v4 signature (RSA, SHA-512) by the yt-dlp signing
/// key. The installer accepts the list only with a valid signature by this key, and the binary only with the hash
/// from that list.
public struct YtDlpSigningKey: Equatable, Sendable {
    /// The OpenPGP v4 fingerprint, upper-case hex; the signature must name it as its issuer.
    public let fingerprint: String
    /// The RSA public key as PKCS #1 DER (`RSAPublicKey`).
    public let rsaPublicKeyDER: Data

    public init(fingerprint: String, rsaPublicKeyDER: Data) {
        self.fingerprint = fingerprint
        self.rsaPublicKeyDER = rsaPublicKeyDER
    }

    /// Throws `HelperInstallError.untrustedRelease` unless `signature` is a valid OpenPGP v4 signature of `data`
    /// (binary document, RSA, SHA-512) by this key.
    public func verify(signature: Data, of data: Data) throws {
        let packet = try OpenPGPSignaturePacket(Array(signature))
        guard packet.issuerFingerprint == fingerprint else {
            throw HelperInstallError.untrustedRelease("yt-dlp: the release is signed by another key")
        }
        var hashed = Data(data)
        hashed.append(contentsOf: packet.hashedArea)
        hashed.append(contentsOf: [0x04, 0xFF])
        hashed.append(contentsOf: UInt32(packet.hashedArea.count).bigEndianBytes)
        let digest = Data(SHA512.hash(data: hashed))
        guard digest.prefix(2) == Data(packet.digestPrefix) else {
            throw HelperInstallError.untrustedRelease("yt-dlp: the checksum list does not match its signature")
        }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
        ]
        guard let key = SecKeyCreateWithData(rsaPublicKeyDER as CFData, attributes as CFDictionary, nil) else {
            throw HelperInstallError.untrustedRelease("yt-dlp: the signing key cannot be read")
        }
        // An OpenPGP MPI drops leading zero bytes; the RSA check needs the full key length.
        let size = SecKeyGetBlockSize(key)
        guard packet.signature.count <= size else {
            throw HelperInstallError.untrustedRelease("yt-dlp: the release signature is malformed")
        }
        let padded = Data(repeating: 0, count: size - packet.signature.count) + Data(packet.signature)
        guard SecKeyVerifySignature(key, .rsaSignatureDigestPKCS1v15SHA512, digest as CFData, padded as CFData, nil) else {
            throw HelperInstallError.untrustedRelease("yt-dlp: the checksum list does not match its signature")
        }
    }
}

extension YtDlpSigningKey {
    /// "Simon Sawicki (yt-dlp signing key)": RSA 4096, created 2023-02-26, `public.key` in the yt-dlp repository.
    public static let ytDlpProject = YtDlpSigningKey(
        fingerprint: "AC0CBBE6848D6A873464AF4E57CF65933B5A7581",
        rsaPublicKeyDER: Data(base64Encoded:
            "MIICCgKCAgEA9Kxfc4xjwLdLYZbeQtXm83HAFV+zW9b/nqkI5PlhGXUxE1QoN1gDOZ4AK5R3Zv32as1IDvqQGKwetBinoO331A3/" +
            "ktFxShGXXkS2HgGqqioUom1WpQ47zgTs7bt1utOxyxE0AKgO8Ez7iLdlqpqS+tDSHMq9uy8apoHTd5jb2doizvmz9Jykfwvj4BPR" +
            "+MrcsA2tdszMej5mQp1Tjjrul2RBZnVMcXUPXxQ6nfS3ASmNiwznEmKNbGmNGFomVh7c1aGbtZDs450uRY6v8gRySyJgx+6TcR5u" +
            "7Pz52rq6ZkBbQxa7pLftpYQ56SlJhq/yP9yB6h/1/vZz6EuLoqkOR6W5QfASvuFn6WohIO+S577jj32SDymMl2v9AO0KIzMIDqw/" +
            "PKM0/lQpCpJCfoo12e4BzY5nAWlHSiu3wyBDmCOty8nOkFpBkE4oBX30lF1hwwjvWlzYT93o6hVoBjLQlLK25HCZFrlmO6uQEcv9" +
            "OR20jNyuA1PXqrZ8ZoldVkPJ17iPSYCUEb4eT05J8uS7cas3Jqr1jvU4xwW67NeATxDvX3F8Si/whQW81w0r7wIAK3aqpTKJ3EP8" +
            "onE5Xy+qsyfBChYqlteEDE3QJ+krrmU6HVwk4iJ8KE+1o47hTyinb3x9Rj+G56nc058y8QkgyBLX8nz7CF/vRiOyZJP82Y0CAwEA" +
            "AQ=="
        )!
    )
}

/// The parts of a detached OpenPGP v4 signature packet (RFC 4880 §5.2.3) that the check reads. Only what yt-dlp
/// publishes is accepted: a binary-document signature, RSA, SHA-512, with an issuer fingerprint in the hashed area.
private struct OpenPGPSignaturePacket {
    let hashedArea: [UInt8]
    let issuerFingerprint: String?
    let digestPrefix: [UInt8]
    let signature: [UInt8]

    init(_ bytes: [UInt8]) throws {
        var reader = ByteReader(bytes)
        let body = try reader.signaturePacketBody()
        var fields = ByteReader(body)
        guard try fields.byte() == 4,          // version 4
              try fields.byte() == 0x00,       // signature of a binary document
              try fields.byte() == 1,          // RSA
              try fields.byte() == 10          // SHA-512
        else { throw Self.malformed }
        let hashedLength = Int(try fields.uint16())
        let hashedSubpackets = try fields.bytes(hashedLength)
        hashedArea = Array(body[0..<(6 + hashedLength)])
        issuerFingerprint = try Self.issuerFingerprint(in: hashedSubpackets)
        _ = try fields.bytes(Int(try fields.uint16()))  // unhashed subpackets
        digestPrefix = try fields.bytes(2)
        let bits = Int(try fields.uint16())
        signature = try fields.bytes((bits + 7) / 8)
    }

    static let malformed = HelperInstallError.untrustedRelease("yt-dlp: the release signature is malformed")

    /// Subpacket 33 (issuer fingerprint): key version 4, then the 20-byte fingerprint.
    private static func issuerFingerprint(in subpackets: [UInt8]) throws -> String? {
        var reader = ByteReader(subpackets)
        while !reader.isAtEnd {
            let length = try reader.subpacketLength()
            guard length > 0 else { throw malformed }
            let content = try reader.bytes(length)
            if content[0] & 0x7F == 33, content.count == 22, content[1] == 4 {
                return content[2...].map { String(format: "%02X", $0) }.joined()
            }
        }
        return nil
    }
}

private struct ByteReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isAtEnd: Bool { offset >= bytes.count }

    mutating func byte() throws -> UInt8 {
        guard offset < bytes.count else { throw OpenPGPSignaturePacket.malformed }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func bytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= bytes.count else { throw OpenPGPSignaturePacket.malformed }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }

    mutating func uint16() throws -> UInt16 {
        try bytes(2).reduce(0) { $0 << 8 | UInt16($1) }
    }

    mutating func uint32() throws -> UInt32 {
        try bytes(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    /// One whole packet with tag 2 (signature), in the old or the new header format; returns its body.
    mutating func signaturePacketBody() throws -> [UInt8] {
        let header = try byte()
        guard header & 0x80 != 0 else { throw OpenPGPSignaturePacket.malformed }
        let tag: UInt8
        let length: Int
        if header & 0x40 != 0 {
            tag = header & 0x3F
            length = try subpacketLength()
        } else {
            tag = (header >> 2) & 0x0F
            switch header & 0x03 {
            case 0: length = Int(try byte())
            case 1: length = Int(try uint16())
            case 2: length = Int(try uint32())
            default: throw OpenPGPSignaturePacket.malformed
            }
        }
        guard tag == 2 else { throw OpenPGPSignaturePacket.malformed }
        let body = try bytes(length)
        guard isAtEnd else { throw OpenPGPSignaturePacket.malformed }
        return body
    }

    /// The new-format length (RFC 4880 §4.2.2), which subpackets use too; partial lengths are refused.
    mutating func subpacketLength() throws -> Int {
        let first = Int(try byte())
        switch first {
        case 0..<192: return first
        case 192..<224:
            let second = Int(try byte())
            return (first - 192) << 8 + second + 192
        case 255: return Int(try uint32())
        default: throw OpenPGPSignaturePacket.malformed
        }
    }
}

private extension UInt32 {
    var bigEndianBytes: [UInt8] {
        [UInt8(self >> 24 & 0xFF), UInt8(self >> 16 & 0xFF), UInt8(self >> 8 & 0xFF), UInt8(self & 0xFF)]
    }
}
