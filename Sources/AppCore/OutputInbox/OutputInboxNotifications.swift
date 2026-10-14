import Foundation

extension Notification.Name {
    /// Posted when the shared output inbox store adds or updates items.
    ///
    /// The object is always `nil`; `userInfo[Notification.outputInboxStorageURLKey]` names the
    /// store file that changed, so an observer can ignore posts from other stores.
    public static let outputInboxDidChange = Notification.Name("NikoMusicHub.outputInboxDidChange")
}

extension Notification {
    /// `userInfo` key on `.outputInboxDidChange`: the standardized storage `URL` of the store that
    /// posted it.
    public static let outputInboxStorageURLKey = "NikoMusicHub.outputInboxStorageURL"

    /// The storage URL of the store that posted this `.outputInboxDidChange`, if any.
    public var outputInboxStorageURL: URL? {
        userInfo?[Notification.outputInboxStorageURLKey] as? URL
    }
}
