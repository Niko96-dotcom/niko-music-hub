import Foundation

public protocol PreferenceStore: Sendable {
    func bool(forKey key: String) -> Bool?
    func set(_ value: Bool, forKey key: String)
    func data(forKey key: String) -> Data?
    func set(_ data: Data, forKey key: String)
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    func removeObject(forKey key: String)
}

public struct UserDefaultsPreferenceStore: PreferenceStore, @unchecked Sendable {
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults) {
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

    public func string(forKey key: String) -> String? {
        userDefaults.string(forKey: key)
    }

    public func set(_ value: String, forKey key: String) {
        userDefaults.set(value, forKey: key)
        userDefaults.synchronize()
    }

    public func removeObject(forKey key: String) {
        userDefaults.removeObject(forKey: key)
        userDefaults.synchronize()
    }
}

/// Preferences that live only in memory: tests, previews and harnesses that must
/// never read or write the person's real defaults. Real defaults come only from
/// the composition root (`AppComposition.makeUserDefaults`), which passes its
/// suite to `UserDefaultsPreferenceStore(userDefaults:)` explicitly.
public final class InMemoryPreferenceStore: PreferenceStore, @unchecked Sendable {
    private let lock = NSLock()
    private var bools: [String: Bool] = [:]
    private var datas: [String: Data] = [:]
    private var strings: [String: String] = [:]

    public init() {}

    public func bool(forKey key: String) -> Bool? { lock.withLock { bools[key] } }
    public func set(_ value: Bool, forKey key: String) { lock.withLock { bools[key] = value } }
    public func data(forKey key: String) -> Data? { lock.withLock { datas[key] } }
    public func set(_ data: Data, forKey key: String) { lock.withLock { datas[key] = data } }
    public func string(forKey key: String) -> String? { lock.withLock { strings[key] } }
    public func set(_ value: String, forKey key: String) { lock.withLock { strings[key] = value } }
    public func removeObject(forKey key: String) {
        lock.withLock {
            bools.removeValue(forKey: key)
            datas.removeValue(forKey: key)
            strings.removeValue(forKey: key)
        }
    }
}
