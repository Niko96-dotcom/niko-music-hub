import AppCore
import XCTest

final class ProjectVaultHealthCopyTests: XCTestCase {
    func testOfflineCopy() {
        XCTAssertEqual(
            ProjectVaultHealthCopy.archiveSidebarLine(.offline),
            "The Project Vault disk is offline. Songs in Active stay on this Mac."
        )
    }

    func testOtherStatusesReuseHealthSummary() {
        for status: ProjectVaultProviderStatus in [.notConfigured, .availableLocal, .availableProvider] {
            let expected = ProjectVaultHealth(
                providerStatus: status,
                lastSuccessfulVerificationAt: nil,
                hasIndependentBackup: false
            ).summary
            XCTAssertEqual(ProjectVaultHealthCopy.archiveSidebarLine(status), expected)
        }
    }

    func testHealthOverloadKeepsOfflineCopyAndSummary() {
        let offline = ProjectVaultHealth(
            providerStatus: .offline,
            lastSuccessfulVerificationAt: nil,
            hasIndependentBackup: false
        )
        XCTAssertEqual(
            ProjectVaultHealthCopy.archiveSidebarLine(offline),
            "The Project Vault disk is offline. Songs in Active stay on this Mac."
        )
        let local = ProjectVaultHealth(
            providerStatus: .availableLocal,
            lastSuccessfulVerificationAt: nil,
            hasIndependentBackup: true
        )
        XCTAssertEqual(ProjectVaultHealthCopy.archiveSidebarLine(local), local.summary)
    }
}
