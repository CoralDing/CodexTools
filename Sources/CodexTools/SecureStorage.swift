/**
 * 文件说明：登录会话的 Keychain 安全存储
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-25
 */

import Foundation
import Security

/// 使用 macOS Keychain 保存访问令牌，避免敏感数据进入 UserDefaults（普通偏好设置文件）。
struct KeychainSessionStore {
    private let service = "com.dingyi60.CodexTools"
    private let account = "sub2api-session"

    /// 编码并保存当前登录会话；已有记录使用原位更新，避免产生重复条目。
    func save(_ session: AuthSession) throws {
        let data = try JSONEncoder().encode(session)
        let query = baseQuery
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CodexToolsError.keychain(status: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw CodexToolsError.keychain(status: updateStatus)
        }
    }

    /// 读取已保存的会话；未登录时返回空值而不是把“未找到”当作异常。
    func load() throws -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CodexToolsError.keychain(status: status)
        }
        return try JSONDecoder().decode(AuthSession.self, from: data)
    }

    /// 删除会话令牌，用于退出登录；重复退出保持幂等，不额外报错。
    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CodexToolsError.keychain(status: status)
        }
    }

    /// 生成所有 Keychain 操作共用的精确查询条件。
    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
