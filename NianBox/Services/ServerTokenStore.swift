import Foundation
import Security
import LocalAuthentication

struct ServerTokenStore {
    private let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "org.nianbox.NianBox.server", kSecAttrAccount as String: "api-token"]
    func load() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        let authentication = LAContext()
        authentication.interactionNotAllowed = true
        request[kSecUseAuthenticationContext as String] = authentication
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw SyncFailure.message("Cannot read the server token from Keychain (\(status)).")
        }
        return token
    }
    func save(_ token: String) throws {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var request = query
            request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else {
                throw SyncFailure.message("Cannot save the API token to Keychain.")
            }
        } else if status != errSecSuccess {
            throw SyncFailure.message("Cannot update the API token in Keychain (\(status)).")
        }
    }
}
