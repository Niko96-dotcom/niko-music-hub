import AppKit
import SwiftUI

enum HubBrandLogo {
    static var sidebar: Image? {
        image(named: "AppLogo-48", extension: "png").map(Image.init(nsImage:))
    }

    private static func image(named name: String, extension ext: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
