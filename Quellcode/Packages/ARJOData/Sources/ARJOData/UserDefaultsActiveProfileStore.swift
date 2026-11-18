import ARJOCore
import Foundation

public struct UserDefaultsActiveProfileStore: ActiveProfileStore, @unchecked Sendable {
    // UserDefaults ist thread-sicher, aber nicht als Sendable markiert.
    private let defaults: UserDefaults
    private let key = "activeProfileID"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var activeProfileID: UUID? {
        defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    public func setActiveProfileID(_ id: UUID?) {
        defaults.set(id?.uuidString, forKey: key)
    }
}
