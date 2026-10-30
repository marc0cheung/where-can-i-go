import Foundation
import CryptoKit
import Security

/// The user's signing key for travel cards.
///
/// The private key lives in the Keychain as a synchronizable item, so iCloud
/// Keychain carries it to the user's other devices and through reinstalls.
/// `sharerID` is the SHA-256 of the public key.
nonisolated enum SharingIdentity {
    private static let service = "com.marcocheung.whereCanIGo.sharing"
    private static let keyAccount = "signing-key"
    private static let revisionAccount = "card-revision"

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
                return String(localized: "Your sharing identity couldn't be accessed. (\(message))")
            }
        }
    }

    /// Returns the existing key, or `nil` when the user has never shared a card.
    static func currentKey() throws -> P256.Signing.PrivateKey? {
        guard let data = try read(account: keyAccount) else { return nil }
        return try P256.Signing.PrivateKey(rawRepresentation: data)
    }

    static func loadOrCreateKey() throws -> P256.Signing.PrivateKey {
        if let key = try currentKey() { return key }
        let key = P256.Signing.PrivateKey()
        try write(key.rawRepresentation, account: keyAccount)
        return key
    }

    static func currentSharerID() throws -> String? {
        try currentKey().map { TravelCardCrypto.sharerID(forPublicKey: $0.publicKey.rawRepresentation) }
    }

    /// The highest revision used so far, or 0.
    static func lastRevision() throws -> Int64 {
        guard let data = try read(account: revisionAccount),
              let value = Int64(String(decoding: data, as: UTF8.self)) else { return 0 }
        return value
    }

    /// Strictly increasing on this identity. The current Unix time is used as a
    /// floor so a reinstall that loses the counter still produces newer cards.
    static func nextRevision(now: Date = Date()) throws -> Int64 {
        let next = max(try lastRevision() + 1, Int64(now.timeIntervalSince1970))
        try write(Data(String(next).utf8), account: revisionAccount)
        return next
    }

    /// Replaces the identity with one restored from a backup.
    static func install(privateKey: Data, lastRevision: Int64) throws {
        let key = try P256.Signing.PrivateKey(rawRepresentation: privateKey)
        let revision = max(lastRevision, try Self.lastRevision())
        try write(key.rawRepresentation, account: keyAccount)
        try write(Data(String(revision).utf8), account: revisionAccount)
    }

    /// Deletes the key and revision counter, including the iCloud Keychain copies.
    /// The next share creates a new identity.
    static func reset() throws {
        for account in [keyAccount, revisionAccount] {
            let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.unexpectedStatus(status)
            }
        }
    }

    // MARK: Keychain

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
    }

    private static func read(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError.unexpectedStatus(status)
        }
    }

    private static func write(_ data: Data, account: String) throws {
        let updateStatus = SecItemUpdate(
            baseQuery(account: account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
        var item = baseQuery(account: account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecAttrSynchronizable as String] = kCFBooleanTrue
        var status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecMissingEntitlement || status == errSecParam {
            // Builds without iCloud Keychain support fall back to a device-only item.
            item[kSecAttrSynchronizable as String] = kCFBooleanFalse
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }
}
