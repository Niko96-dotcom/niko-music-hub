import AppCore
import CryptoKit
import Foundation
import Security

/// A throwaway RSA key that signs checksum lists the way yt-dlp releases do (OpenPGP v4, binary document, RSA,
/// SHA-512, issuer fingerprint in the hashed area), so tests can serve signed yt-dlp releases.
enum TestYtDlpSigner {
    static let fingerprint = String(repeating: "AB", count: 20)
    static let releaseTag = "2026.10.26"

    /// The private key's external representation; a `SecKey` is rebuilt from it for each signature.
    private static let privateKeyData: Data = {
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048]
        let key = SecKeyCreateRandomKey(attributes as CFDictionary, nil)!
        return SecKeyCopyExternalRepresentation(key, nil)! as Data
    }()

    static let key: YtDlpSigningKey = {
        let publicKey = SecKeyCopyPublicKey(privateKey)!
        return YtDlpSigningKey(fingerprint: fingerprint, rsaPublicKeyDER: SecKeyCopyExternalRepresentation(publicKey, nil)! as Data)
    }()

    static func signature(of data: Data, issuer: String = fingerprint) -> Data {
        let issuerBytes = stride(from: 0, to: 40, by: 2).map { offset -> UInt8 in
            UInt8(issuer.dropFirst(offset).prefix(2), radix: 16)!
        }
        let subpacket: [UInt8] = [22, 33, 4] + issuerBytes
        let hashedArea: [UInt8] = [4, 0x00, 1, 10, 0, UInt8(subpacket.count)] + subpacket
        var input = data
        input.append(contentsOf: hashedArea)
        input.append(contentsOf: [0x04, 0xFF, 0, 0, 0, UInt8(hashedArea.count)])
        let digest = Data(SHA512.hash(data: input))
        let rsa = SecKeyCreateSignature(privateKey, .rsaSignatureDigestPKCS1v15SHA512, digest as CFData, nil)! as Data
        let magnitude = Array(rsa.drop(while: { $0 == 0 }))
        let bits = magnitude.count * 8 - magnitude[0].leadingZeroBitCount
        var body = hashedArea
        body += [0, 0]  // no unhashed subpackets
        body += Array(digest.prefix(2))
        body += [UInt8(bits >> 8), UInt8(bits & 0xFF)]
        body += magnitude
        // Old-format header, tag 2 (signature), two-byte length.
        return Data([0x89, UInt8(body.count >> 8), UInt8(body.count & 0xFF)] + body)
    }

    /// The release information GitHub's API returns, reduced to the field the installer reads.
    static func releaseJSON(tag: String = releaseTag) -> String {
        #"{"tag_name": "\#(tag)"}"#
    }

    private static var privateKey: SecKey {
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate]
        return SecKeyCreateWithData(privateKeyData as CFData, attributes as CFDictionary, nil)!
    }
}
