import Foundation

/// Why the updater refuses to run.
///
/// Every case is a build/packaging mistake rather than a runtime condition: an
/// app that ships without a usable feed and key must say so plainly instead of
/// quietly behaving like a product that is already up to date.
public enum AppUpdateConfigurationError: Error, Equatable, Sendable {
    case missingFeedURL
    case malformedFeedURL(String)
    case insecureFeedURL(String)
    case missingPublicKey
    case malformedPublicKey

    public var message: String {
        switch self {
        case .missingFeedURL:
            return "This build has no update feed configured, so it cannot check for updates."
        case .malformedFeedURL(let value):
            return "This build has an unusable update feed address (\(value))."
        case .insecureFeedURL(let scheme):
            return "This build's update feed uses \(scheme) instead of HTTPS, so update checks are disabled."
        case .missingPublicKey:
            return "This build has no update signing key, so downloaded updates could not be verified."
        case .malformedPublicKey:
            return "This build's update signing key is not a valid EdDSA public key."
        }
    }
}

/// The signed-feed contract baked into a bundle at build time.
///
/// `Info.plist` is written by `script/lib/app_lifecycle.sh` from the canonical
/// `SPARKLE_PUBLIC_ED_KEY` file. When that file is absent the keys are omitted
/// entirely, which lands here as a refusal rather than an unverified update.
public struct AppUpdateConfiguration: Equatable, Sendable {
    /// Length in bytes of a raw ed25519 public key.
    static let publicKeyByteCount = 32

    public let feedURL: URL
    public let publicEDKey: String

    public init(feedURL: URL, publicEDKey: String) {
        self.feedURL = feedURL
        self.publicEDKey = publicEDKey
    }

    public static func resolve(
        infoDictionary: [String: Any]
    ) -> Result<AppUpdateConfiguration, AppUpdateConfigurationError> {
        guard let rawFeed = nonEmptyString(infoDictionary["SUFeedURL"]) else {
            return .failure(.missingFeedURL)
        }
        guard let feedURL = URL(string: rawFeed), let scheme = feedURL.scheme, feedURL.host != nil else {
            return .failure(.malformedFeedURL(rawFeed))
        }
        guard scheme.lowercased() == "https" else {
            return .failure(.insecureFeedURL(scheme.lowercased()))
        }
        guard let rawKey = nonEmptyString(infoDictionary["SUPublicEDKey"]) else {
            return .failure(.missingPublicKey)
        }
        guard let decoded = Data(base64Encoded: rawKey), decoded.count == publicKeyByteCount else {
            return .failure(.malformedPublicKey)
        }
        return .success(AppUpdateConfiguration(feedURL: feedURL, publicEDKey: rawKey))
    }

    public static func resolve(
        bundle: Bundle = .main
    ) -> Result<AppUpdateConfiguration, AppUpdateConfigurationError> {
        resolve(infoDictionary: bundle.infoDictionary ?? [:])
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
