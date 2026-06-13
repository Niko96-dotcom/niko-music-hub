import Foundation

public protocol PreferenceStore: Sendable {
    func bool(forKey key: String) -> Bool?
    func set(_ value: Bool, forKey key: String)
    func data(forKey key: String) -> Data?
    func set(_ data: Data, forKey key: String)
    func removeObject(forKey key: String)
}

public struct UserDefaultsPreferenceStore: PreferenceStore, @unchecked Sendable {
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func bool(forKey key: String) -> Bool? {
        guard userDefaults.object(forKey: key) != nil else { return nil }
        return userDefaults.bool(forKey: key)
    }

    public func set(_ value: Bool, forKey key: String) {
        userDefaults.set(value, forKey: key)
        userDefaults.synchronize()
    }

    public func data(forKey key: String) -> Data? {
        userDefaults.data(forKey: key)
    }

    public func set(_ data: Data, forKey key: String) {
        userDefaults.set(data, forKey: key)
        userDefaults.synchronize()
    }

    public func removeObject(forKey key: String) {
        userDefaults.removeObject(forKey: key)
        userDefaults.synchronize()
    }
}
