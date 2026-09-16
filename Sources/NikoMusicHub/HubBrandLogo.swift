import AppKit
import SwiftUI

enum HubBrandLogo {
    /// Preferred sidebar asset (NMH-135). 96 px covers 26 pt @2x (52 px);
    /// the 48 px asset is a bundle fallback only. Both PNGs are copied into
    /// the bundle by `script/lib/app_lifecycle.sh`.
    static let sidebarResourceName = "AppLogo-96"
    static let sidebarFallbackResourceName = "AppLogo-48"

    static var sidebar: Image? {
        (image(named: sidebarResourceName, extension: "png")
            ?? image(named: sidebarFallbackResourceName, extension: "png"))
            .map(Image.init(nsImage:))
    }

    private static func image(named name: String, extension ext: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
