import XCTest
@testable import AppUpdates

final class AppUpdateConfigurationTests: XCTestCase {
    private let validKey = "K65HtaNTCi1P7asVd5OsP/jzkJiFZxWzL483+kX/jP0="
    private let feed = "https://github.com/Niko96-dotcom/niko-music-hub/releases/latest/download/appcast.xml"

    private func resolve(_ info: [String: Any]) -> Result<AppUpdateConfiguration, AppUpdateConfigurationError> {
        AppUpdateConfiguration.resolve(infoDictionary: info)
    }

    private func failure(_ info: [String: Any]) throws -> AppUpdateConfigurationError {
        switch resolve(info) {
        case .success(let configuration):
            XCTFail("expected refusal, got \(configuration)")
            throw XCTSkip("unreachable")
        case .failure(let error):
            return error
        }
    }

    func testResolvesCompleteConfiguration() throws {
        let resolved = try resolve(["SUFeedURL": feed, "SUPublicEDKey": validKey]).get()
        XCTAssertEqual(resolved.feedURL.absoluteString, feed)
        XCTAssertEqual(resolved.publicEDKey, validKey)
    }

    func testTrimsSurroundingWhitespace() throws {
        let resolved = try resolve([
            "SUFeedURL": "  \(feed)\n",
            "SUPublicEDKey": "\t\(validKey)  ",
        ]).get()
        XCTAssertEqual(resolved.feedURL.absoluteString, feed)
        XCTAssertEqual(resolved.publicEDKey, validKey)
    }

    /// A bundle built without update keys must refuse, never silently behave like
    /// a product that is already up to date.
    func testRefusesBundleWithoutFeed() throws {
        XCTAssertEqual(try failure(["SUPublicEDKey": validKey]), .missingFeedURL)
        XCTAssertEqual(try failure(["SUFeedURL": "   ", "SUPublicEDKey": validKey]), .missingFeedURL)
    }

    func testRefusesNonHTTPSFeed() throws {
        let error = try failure(["SUFeedURL": "http://example.com/appcast.xml", "SUPublicEDKey": validKey])
        XCTAssertEqual(error, .insecureFeedURL("http"))
    }

    func testRefusesMalformedFeed() throws {
        let error = try failure(["SUFeedURL": "not a url at all", "SUPublicEDKey": validKey])
        XCTAssertEqual(error, .malformedFeedURL("not a url at all"))
    }

    func testRefusesMissingPublicKey() throws {
        XCTAssertEqual(try failure(["SUFeedURL": feed]), .missingPublicKey)
    }

    /// An ed25519 public key is exactly 32 raw bytes; anything else could never
    /// validate a real enclosure signature.
    func testRefusesPublicKeyOfWrongLength() throws {
        let shortKey = Data(repeating: 0, count: 31).base64EncodedString()
        let longKey = Data(repeating: 0, count: 33).base64EncodedString()
        XCTAssertEqual(try failure(["SUFeedURL": feed, "SUPublicEDKey": shortKey]), .malformedPublicKey)
        XCTAssertEqual(try failure(["SUFeedURL": feed, "SUPublicEDKey": longKey]), .malformedPublicKey)
    }

    func testRefusesPublicKeyThatIsNotBase64() throws {
        let error = try failure(["SUFeedURL": feed, "SUPublicEDKey": "!!!! not base64 !!!!"])
        XCTAssertEqual(error, .malformedPublicKey)
    }

    func testEveryRefusalCarriesAMessage() {
        let errors: [AppUpdateConfigurationError] = [
            .missingFeedURL,
            .malformedFeedURL("x"),
            .insecureFeedURL("http"),
            .missingPublicKey,
            .malformedPublicKey,
        ]
        for error in errors {
            XCTAssertFalse(error.message.isEmpty, "\(error) has no user-facing message")
        }
    }
}
