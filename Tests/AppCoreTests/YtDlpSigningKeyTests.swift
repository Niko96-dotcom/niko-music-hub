import AppCore
import XCTest

/// The yt-dlp signing key against a real release: yt-dlp 2026.10.26's `SHA2-256SUMS` (SHA-256
/// 0d7ec4303a02bcbe66154d478852cdf2e07688d39dc4597316e4424ac4e74356) and its `SHA2-256SUMS.sig`, as published.
final class YtDlpSigningKeyTests: XCTestCase {
    func testTheRealReleaseVerifiesWithTheShippedKey() throws {
        XCTAssertNoThrow(try YtDlpSigningKey.ytDlpProject.verify(signature: Self.realSignature, of: Self.realSums))
    }

    func testOneChangedByteInTheListFailsTheSignature() {
        var sums = Self.realSums
        sums[0] ^= 0x01
        XCTAssertThrowsError(try YtDlpSigningKey.ytDlpProject.verify(signature: Self.realSignature, of: sums)) {
            XCTAssertEqual($0 as? HelperInstallError, .untrustedRelease("yt-dlp: the checksum list does not match its signature"))
        }
    }

    func testASignatureFromAnotherKeyIsRefused() {
        let signature = TestYtDlpSigner.signature(of: Self.realSums)
        XCTAssertThrowsError(try YtDlpSigningKey.ytDlpProject.verify(signature: signature, of: Self.realSums)) {
            XCTAssertEqual($0 as? HelperInstallError, .untrustedRelease("yt-dlp: the release is signed by another key"))
        }
    }

    /// The issuer fingerprint is only a label: a signature that names the right key but was made by another one
    /// still fails the RSA check.
    func testAForgedIssuerFailsTheRSACheck() {
        let forged = TestYtDlpSigner.signature(of: Self.realSums, issuer: YtDlpSigningKey.ytDlpProject.fingerprint)
        XCTAssertThrowsError(try YtDlpSigningKey.ytDlpProject.verify(signature: forged, of: Self.realSums)) {
            XCTAssertEqual($0 as? HelperInstallError, .untrustedRelease("yt-dlp: the checksum list does not match its signature"))
        }
    }

    func testTruncatedOrEmptySignaturesAreRefusedWithoutACrash() {
        for length in [0, 1, 3, 20, Self.realSignature.count - 1] {
            XCTAssertThrowsError(
                try YtDlpSigningKey.ytDlpProject.verify(signature: Self.realSignature.prefix(length), of: Self.realSums),
                "length \(length)"
            )
        }
    }

    func testTheTestSignerMatchesTheFormat() {
        let data = Data("checksums".utf8)
        XCTAssertNoThrow(try TestYtDlpSigner.key.verify(signature: TestYtDlpSigner.signature(of: data), of: data))
    }

    private static let realSums = Data(base64Encoded:
        "ZTUxZTY5ZTg5NDg5ZjE5OTUzMGYxM2QzMmE0MzQyZGEzZGRiMmNmMzQ4NDJmMzY0NjAzYTA2NmRiMDVhZmJmMyAgeXQtZGxwCmY1" +
        "Mzg5ZDM2OThlY2RlNGVmMDZmNGU2YjFjZTAyOTRmZTlhYzEzOTYyMjhjODk5MGI4ZDM0MTZkNmQxNzdhN2QgIHl0LWRscC5leGUK" +
        "MjFmOTQyZDI1OGQyNWNjNGU2MGI0OTgyYTI1YzQyMzQ2MGYwYmViYjgzNWYzOGU2ZGZkMWZjYjE0MDA4N2Y5NSAgeXQtZGxwLnRh" +
        "ci5negowMDY2ZGJhYzNjMTI0MDI4ZTJkY2FlMmExOTdmY2NlZTMzY2Q5MWY0NTYzMTNkMjRmN2FmODlmZDU0NTkwZTk4ICB5dC1k" +
        "bHBfYXJtNjQuZXhlCjc2N2JhOWRjZTcwNTJhYTE5NmY4YjEyNjUyZjQzM2Q3NmRlMTI4YmExNjg5NjZmYTg0YjYzOTRkNWU2YzY3" +
        "OTUgIHl0LWRscF9saW51eApmMzQwNTM0MTUxMzZlNTUwNzNkZDY0YmE1MzI2ZDE2MWVjYzIzY2UwZTk4YzA4MWQ4NzUyODY3YjM3" +
        "ODA5NDUwICB5dC1kbHBfbGludXguemlwCmU4N2U5NTMzZTg5ZmU1ODg5YWJhYTIxZjUxMTRkZmU3NzU2ZDZhYTYyMTliODM1NTFh" +
        "ZGQwNGQ0OGIxOGU0ODMgIHl0LWRscF9saW51eF9hYXJjaDY0Cjc0NzA4ZTcwN2U4ZmE4MTc3YzgzNDdlNTgxNTIzMzdlZGYzMjAx" +
        "NDljZDdiMjI1ZGVmZDQ1M2Y3Y2RlNDc4MjIgIHl0LWRscF9saW51eF9hYXJjaDY0LnppcAplYzgyOGMyNmM2ZGE3ODk4YjI3OWRh" +
        "MmNhZDNkY2E0MzRlYmVjN2Y4ZjE4YWU3YjY0MjAwMjdmM2FhMDM3YmYyICB5dC1kbHBfbGludXhfYXJtdjdsLnppcAowZjkyMmMx" +
        "NWNjYzBiODNlZWZhMWM4YmM5MTA0ZTQzNDMxOGM0YmYxNmU0MDhlMWVlOTNiNzc0NWE2ZWZlMGFhICB5dC1kbHBfbWFjb3MKMjBk" +
        "OThmYTYwODk5OGVmZjg3ZDFkMzVhNmU5ZmI2NWU0Yjg3NDYzOWE2Y2M4OWFkZGMxOWRhM2JlY2RlM2VmMSAgeXQtZGxwX21hY29z" +
        "LnppcAplOTdhNGRkOTE5MjIxZDIzM2U3NzIwZTE4ZmEzZjY2ZGI2MGZiZDFkOGMwODQ2YmY2ZGViOGU4OGUwNDQ3NWE4ICB5dC1k" +
        "bHBfbXVzbGxpbnV4CmMzYTY3ZjdjMTRkNGNiZjg3NmU3ODAxMDM5MjM3ZmMxNmI5MjlhNjI5YzcyZjljNzg1ZWMzZmRjOGFhNDA3" +
        "NDggIHl0LWRscF9tdXNsbGludXguemlwCmVhOTdiODU2NDY2N2YzY2FiYzMzNGMzMjE2NTI2ZGUzOWJjNjg0ZTk5ODE1ZWNmMDdi" +
        "NjY0MmY0Y2JhOGFmNGQgIHl0LWRscF9tdXNsbGludXhfYWFyY2g2NAoxNjQ4YmVlYjdiMGM3OGI0NzE2NTQyNjI2OTcwNjZjMDE2" +
        "NzgzZDMzODEzNjU5MzY3YTVjMjc0ODI4YmEzMjQwICB5dC1kbHBfbXVzbGxpbnV4X2FhcmNoNjQuemlwCmZkNTFiMjEyY2Y4Mzgw" +
        "YzdhNTJlZTA4YzBkNmJlN2YzYzU5YjJmMmM4MzJlYWY3YjQ1YWNmYWU2ZWFiNTc0MTkgIHl0LWRscF93aW4uemlwCjVlYWE0YzYx" +
        "ZjNjMDkxODlmM2E1NTFiZjE4NTVjMTNhYWQ2MWZiODY1Y2MzM2YwNjAxMmE2YzJkYmUyODdhNDUgIHl0LWRscF93aW5fYXJtNjQu" +
        "emlwCmUyODk4YWZkNTFjMDI5ZDIzYzU4ZGU2MGNkODQ0NmIxMTBkZDNhYTEyMWIzZTQxNDliYWZjZWUzMzU2YzU5YzAgIHl0LWRs" +
        "cF93aW5feDg2LnppcApjMDQwN2M2NjM2MWY1MGE5OWUxMDk0OWFlODgyZWEyYWQ3ZGU5MDg2Yjc1ZDIyNmQ4ZmQ4OGRhNGY3NDgy" +
        "OGZhICB5dC1kbHBfeDg2LmV4ZQo="
    )!

    private static let realSignature = Data(base64Encoded:
        "iQIzBAABCgAdFiEErAy75oSNaoc0ZK9OV89lkztadYEFAmrf0ykACgkQV89lkztadYFrgRAAi88f07ETAUGIzH/ifgZLMdYcQavM" +
        "pBw5GsbCi4Os7K2+MJNZgJ1SpTYa/qQZ0GPS+RCsebOPcbByTAt9OSjnN7ZzJVPbl8B/FioDRWBond7Z3JvZojU28Xv6dd0YGv7s" +
        "w0pNit1Rro+9qtxQ1ibiNlqZHyj8BHyANOvSNNRLJuVmDkXWirmQwAjHnTmnK3Qcg2dOmuQr5DX/XbeNqzxxcqphUO7upijylfOt" +
        "VQyKoY91ze41k0XE4H1e+jdn8OuZEZhw2h/UEk9EX5ENn6jAqOPN3c0t33vUgZqYUliDnYogSC2ITb8tbsxdMRnQG5HouYLHVK56" +
        "aPClkx5sm/891XpwYw2xF8RIqqDEt9yf+V0xbd2rJBOvjQmPMJ6iLUbaBI440VRaJDd5ZEkMAGd+O8xxMQ+xf/SvPpFM8ytAgxk+" +
        "B76xTYv/2Z9FiMC08Au0iXkEaJ72ws/i0Ly55BvZ8bbON3yMrk64WG3JHoQo0xF+1K1YuWjpXxkesseLlj6fPcNlcAKjK2mzKV5E" +
        "Qe+ZPdCzWy4+BM3tQybyrUkHYQkJnCUad1a2/ufpnZFy1sFm/SM+o71Sf3qLYFz/BP6RVSnChN5DvuxN+hPZfL4dqubxUIXZAAYx" +
        "t1dss2NhqBc7BdhbetJwmt/foI8NLAiKYp6D5Rhv1zhdajQta+BlF78="
    )!
}
