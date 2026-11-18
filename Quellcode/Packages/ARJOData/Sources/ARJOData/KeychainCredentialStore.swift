import ARJOCore
import Foundation
import Security

public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case corruptData
}

/// Legt Zugangsdaten als JSON in einem generischen Keychain-Eintrag pro Profil ab.
/// Mit `synchronizable` laufen sie über den iCloud-Schlüsselbund auf alle Geräte.
public struct KeychainCredentialStore: CredentialStore {
    private let service: String
    private let synchronizable: Bool

    public init(service: String = "ch.arjo.iptelevision.credentials", synchronizable: Bool = true) {
        self.service = service
        self.synchronizable = synchronizable
    }

    public func save(_ credentials: SourceCredentials, for profileID: UUID) throws {
        let data = try JSONEncoder().encode(credentials)
        try delete(for: profileID)

        var attributes = baseQuery(for: profileID)
        #if !os(macOS) // Ohne Team-Entitlements (ad-hoc signierte Mac-App) gibt es nur die klassische Keychain ohne iCloud-Sync.
        attributes[kSecAttrSynchronizable as String] = synchronizable
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        #endif
        attributes[kSecValueData as String] = data
        try check(SecItemAdd(attributes as CFDictionary, nil))
    }

    public func load(for profileID: UUID) throws -> SourceCredentials? {
        var query = baseQuery(for: profileID)
        #if !os(macOS)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        #endif
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)

        guard let data = result as? Data,
              let credentials = try? JSONDecoder().decode(SourceCredentials.self, from: data)
        else { throw KeychainError.corruptData }
        return credentials
    }

    public func delete(for profileID: UUID) throws {
        var query = baseQuery(for: profileID)
        #if !os(macOS)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        #endif
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func baseQuery(for profileID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
        ]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }
}
