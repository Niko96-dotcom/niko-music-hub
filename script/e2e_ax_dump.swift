import ApplicationServices
import Foundation

guard let pidValue = ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_AX_PID"],
      let pid = pid_t(pidValue) else {
    fputs("NIKO_MUSIC_HUB_AX_PID is required\n", stderr)
    exit(2)
}

let app = AXUIElementCreateApplication(pid)

func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success, let value else { return "" }
    return String(describing: value)
}

func children(of element: AXUIElement) -> [AXUIElement] {
    elements(for: kAXChildrenAttribute, of: element)
}

func windows(of element: AXUIElement) -> [AXUIElement] {
    elements(for: kAXWindowsAttribute, of: element)
}

func elements(for attribute: String, of element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success, let array = value as? [AXUIElement] else { return [] }
    return array
}

func dump(_ element: AXUIElement, depth: Int) {
    guard depth <= 6 else { return }

    let role = stringAttribute(element, kAXRoleAttribute)
    let title = stringAttribute(element, kAXTitleAttribute)
    let value = stringAttribute(element, kAXValueAttribute)

    if !title.isEmpty || !value.isEmpty {
        print("\(String(repeating: "  ", count: depth))\(role) title=\(title) value=\(value)")
    }

    for child in children(of: element) {
        dump(child, depth: depth + 1)
    }

    if depth == 0 {
        for window in windows(of: element) {
            dump(window, depth: depth + 1)
        }
    }
}

dump(app, depth: 0)
