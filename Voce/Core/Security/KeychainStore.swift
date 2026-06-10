import Foundation
import Security

struct KeychainStore {
    private let service: String
    private let account: String

    init(
        service: String = "com.sgstq.voce",
        account: String = "openai-api-key"
    ) {
        self.service = service
        self.account = account
    }

    func read() throws -> String? {
        try read(account: account)
    }

    func read(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        return String(data: data, encoding: .utf8)
    }

    func save(_ value: String) throws {
        try save(value, account: account)
    }

    func save(_ value: String, account: String) throws {
        guard !value.isEmpty else {
            try delete(account: account)
            return
        }

        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery(account: account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(updateStatus)
        }

        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        let addStatus = SecItemAdd(query as CFDictionary, nil)

        guard addStatus == errSecSuccess else {
            throw KeychainError.unhandledStatus(addStatus)
        }
    }

    func delete() throws {
        try delete(account: account)
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum KeychainError: LocalizedError {
    case invalidData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            "The saved API key could not be decoded."
        case .unhandledStatus(let status):
            "Keychain operation failed with status \(status)."
        }
    }
}
