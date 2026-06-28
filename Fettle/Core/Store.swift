import Foundation

/// Tiny typed wrapper over `UserDefaults` for persisting tool preferences.
/// Tools read defaults in `init` and write in `didSet`, so `@Observable`
/// tracking keeps working (no custom property wrapper to interfere).
enum Store {
    private static let defaults = UserDefaults.standard

    static func bool(_ key: String, default def: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? def
    }
    static func double(_ key: String, default def: Double) -> Double {
        defaults.object(forKey: key) as? Double ?? def
    }
    static func int(_ key: String, default def: Int) -> Int {
        defaults.object(forKey: key) as? Int ?? def
    }
    static func string(_ key: String, default def: String) -> String {
        defaults.string(forKey: key) ?? def
    }

    /// Decodes a `RawRepresentable` enum, falling back to `def`.
    static func rawValue<T: RawRepresentable>(_ key: String, default def: T) -> T where T.RawValue == String {
        guard let raw = defaults.string(forKey: key), let value = T(rawValue: raw) else { return def }
        return value
    }

    static func set(_ value: Bool, _ key: String) { defaults.set(value, forKey: key) }
    static func set(_ value: Double, _ key: String) { defaults.set(value, forKey: key) }
    static func set(_ value: Int, _ key: String) { defaults.set(value, forKey: key) }
    static func set(_ value: String, _ key: String) { defaults.set(value, forKey: key) }
    static func set<T: RawRepresentable>(_ value: T, _ key: String) where T.RawValue == String {
        defaults.set(value.rawValue, forKey: key)
    }
}
