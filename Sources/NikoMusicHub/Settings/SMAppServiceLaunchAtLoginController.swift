import AppCore
import Foundation
import ServiceManagement

@MainActor
final class SMAppServiceLaunchAtLoginController: LaunchAtLoginControlling {
    func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            throw LaunchAtLoginError.registrationFailed(error.localizedDescription)
        }
    }
}
