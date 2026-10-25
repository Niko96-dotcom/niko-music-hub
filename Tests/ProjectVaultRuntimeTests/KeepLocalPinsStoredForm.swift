import AppCore
import Foundation

/// Tests plant and read Keep Local keys in the form settings store them, the array older builds wrote,
/// through the settings codec. The raw set is private to `KeepLocalPins` (ADR 021); product code asks
/// `contains`, `pin` and `unpin`.
extension KeepLocalPins {
    init(storedForm keys: Set<String>) {
        self = try! JSONDecoder().decode(KeepLocalPins.self, from: JSONEncoder().encode(keys))
    }

    var storedForm: Set<String> {
        get { try! JSONDecoder().decode(Set<String>.self, from: JSONEncoder().encode(self)) }
        set { self = KeepLocalPins(storedForm: newValue) }
    }
}
