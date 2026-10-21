import CryptoKit
import Foundation

/// A settings suite isolates app stores, but AppKit writes to the bundle's
/// preferences domain. Fixture bundles therefore need both identities.
public enum IsolatedAppLaunch {
    public static let suiteInfoKey = "NMHIsolatedSettingsSuite"
    public static let canonicalIDInfoKey = "NMHCanonicalBundleIdentifier"

    public static func bundleIdentifier(canonical: String, suite: String) -> String {
        let digest = SHA256.hash(data: Data(suite.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return canonical + ".isolated." + digest
    }

    /// Finder/LaunchServices relaunches must keep the suite even without the
    /// original environment. A conflicting override or a production bundle
    /// with a suite is refused before SwiftUI/AppKit creates the application.
    public static func settingsSuite(
        requested: String?, declared: String?, bundleID: String?, canonicalID: String?
    ) throws -> String? {
        let requested = requested?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard let declared, !declared.isEmpty,
              let canonicalID, !canonicalID.isEmpty,
              declared != canonicalID,
              declared.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil,
              bundleID == bundleIdentifier(canonical: canonicalID, suite: declared),
              requested == nil || requested == declared else {
            if requested == nil, declared == nil, canonicalID == nil,
               bundleID?.contains(".isolated.") != true { return nil }
            throw UnsafeSuiteLaunch()
        }
        return declared
    }

    private struct UnsafeSuiteLaunch: LocalizedError {
        var errorDescription: String? {
            "Isolated settings require an isolated app bundle. Use the project launch helpers; use a separate macOS account to test the unchanged release app."
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
