import Foundation
import SwiftUI

extension KeyPress.Result {
    /// Handles the key and makes `change` on the next main-queue turn, after the current view update.
    ///
    /// SwiftUI calls an `onKeyPress` action inside a view update, and an observable object that publishes
    /// there is undefined behavior: the running app logged the "Publishing changes from within view updates"
    /// fault on every Esc and Return in the archive and every Space and Esc on the BPM tap pad (live check,
    /// 2026-10-27). So an action decides at once whether it handles the key, and hands its change to this.
    /// `KeyPressSourceTests` keeps every handled key on this path; design contract §4.
    @MainActor
    public static func handledAfterViewUpdate(_ change: @escaping @MainActor () -> Void) -> KeyPress.Result {
        DispatchQueue.main.async { change() }
        return .handled
    }
}
