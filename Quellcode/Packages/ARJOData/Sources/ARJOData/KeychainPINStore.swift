import ARJOCore
import CryptoKit
import Foundation
import Security

/// Speichert die Kindersicherungs-PIN als gesalzenen SHA-256-Hash in der Keychain.
/// Eine 4- bis 6-stellige PIN ist ohnehin nur ein Schutz gegen Kinder, nicht gegen Angreifer mit Geräte-Zugriff.
public struct KeychainPINStore: PINStore {
    private struct Stored: Codable {
        var salt: Data
        var hash: Data
    }

    private let service: String
    private let synchronizable: Bool
    private let account = "parental-pin"

    public init(service: String = "ch.arjo.iptelevision.parental", synchronizable: Bool = true) {
        self.service = service
        self.synchronizable = synchronizable
    }

    public var hasPIN: Bool {
        get throws { try load() != nil }
    }

    public func setPIN(_ pin: String) throws {
        let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        let stored = Stored(salt: salt, hash: Self.hash(pin, salt: salt))
        try removePIN()

        var attributes = baseQuery()
        #if !os(macOS) // Ohne Team-Entitlements (ad-hoc signierte Mac-App) gibt es nur die klassische Keychain ohne iCloud-Sync.
        attributes[kSecAttrSynchronizable as String] = synchronizable
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        #endif
        attributes[kSecValueData as String] = try JSONEncoder().encode(stored)
        try check(SecItemAdd(attributes as CFDictionary, nil))
    }

    public func verify(_ pin: String) throws -> Bool {
        guard let stored = try load() else { return false }
        return Self.hash(pin, salt: stored.salt) == stored.hash
    }

    public func removePIN() throws {
        var query = baseQuery()
        #if !os(macOS)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        #endif
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func load() throws -> Stored? {
        var query = baseQuery()
        #if !os(macOS)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        #endif
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            throw KeychainError.corruptData
        }
        return stored
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    private static func hash(_ pin: String, salt: Data) -> Data {
        Data(SHA256.hash(data: salt + Data(pin.utf8)))
    }
}
