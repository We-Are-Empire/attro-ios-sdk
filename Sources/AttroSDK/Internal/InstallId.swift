import Foundation
import Security

/// Source of the SDK-generated install id (contract §3: "an SDK-generated
/// UUID, stored in the Keychain for the life of the install").
protocol InstallIdStore: Sendable {
    func installId() -> String
}

/// Keychain-backed install id: a random UUID, created on first use, stored as
/// a generic password readable after first unlock and never synced or backed
/// up to another device (`...ThisDeviceOnly`). It is not derived from any
/// device property.
///
/// If the Keychain is unavailable (for example an unsigned macOS test host),
/// the id falls back to UserDefaults so attribution still works; the failure
/// is logged.
final class KeychainInstallIdStore: InstallIdStore, @unchecked Sendable {
    private let service: String
    private let account = "installId"
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var cached: String?

    init(service: String = "com.attro.sdk", defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    func installId() -> String {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let id = readKeychain() ?? createId()
        cached = id
        return id
    }

    private var fallbackKey: String { "com.attro.sdk.v2.installId" }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func readKeychain() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let id = String(data: data, encoding: .utf8), !id.isEmpty {
            return id
        }
        if status != errSecItemNotFound {
            AttroLog.error("Keychain read for the install id failed (\(status)); using the fallback store.")
        }
        return defaults.string(forKey: fallbackKey)
    }

    private func createId() -> String {
        let id = UUID().uuidString.lowercased()
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(id.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            AttroLog.error("Keychain write for the install id failed (\(status)); using the fallback store.")
            defaults.set(id, forKey: fallbackKey)
        }
        return id
    }
}

/// Test double.
final class FixedInstallIdStore: InstallIdStore {
    let id: String
    init(_ id: String) { self.id = id }
    func installId() -> String { id }
}
