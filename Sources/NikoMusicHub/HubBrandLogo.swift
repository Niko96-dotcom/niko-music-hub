import AppKit
import SwiftUI

enum HubBrandLogo {
    static var sidebar: Image? {
        image(named: "AppLogo-48", extension: "png").map(Image.init(nsImage:))
    }

    static func installApplicationIcon() {
        guard let icon = applicationIcon else { return }
        NSApp.applicationIconImage = icon
    }

    private static var applicationIcon: NSImage? {
        if let icns = image(named: "AppIcon", extension: "icns") {
            return icns
        }
        return image(named: "AppLogo-96", extension: "png")
    }

    private static func image(named name: String, extension ext: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
