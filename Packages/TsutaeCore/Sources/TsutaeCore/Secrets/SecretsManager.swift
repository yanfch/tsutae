import Foundation
import Security

/// Secrets 管理器 — macOS Keychain 封装
/// 对应文档: gui-tui/docs/09-paths.md (§密钥管理)
///
/// API Key 等敏感信息存 Keychain，配置文件里只放引用名。
/// 命名规范: `<app>.<engine>_<purpose>`（如 `tsutae.openai_api_key`）
public enum SecretsManager {
    
    private static let service = "dev.yanfch.tsutae"
    nonisolated(unsafe) private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: CachedSecret] = [:]
    
    // MARK: - 存取
    
    /// 保存 secret
    /// - Parameters:
    ///   - name: 引用名（如 `notion_token`）
    ///   - value: 密钥值
    public static func set(_ value: String, for name: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw SecretsError.invalidValue
        }
        
        // 先尝试更新
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrModificationDate as String: Date(),
        ]
        
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        if status == errSecItemNotFound {
            // 不存在，创建新的
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrCreationDate as String] = Date()
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        
        guard status == errSecSuccess else {
            throw SecretsError.keychainError(status)
        }
        setCachedSecret(.value(value), for: name)
    }
    
    /// 读取 secret
    /// - Parameter name: 引用名
    /// - Returns: 密钥值（不存在返回 nil）
    public static func get(_ name: String) throws -> String? {
        if let cached = cachedSecret(for: name) {
            switch cached {
            case .value(let value):
                return value
            case .missing:
                return nil
            }
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            setCachedSecret(.missing, for: name)
            return nil
        }
        
        guard status == errSecSuccess, let data = result as? Data else {
            throw SecretsError.keychainError(status)
        }
        
        let value = String(data: data, encoding: .utf8)
        if let value {
            setCachedSecret(.value(value), for: name)
        }
        return value
    }
    
    /// 删除 secret
    /// - Parameter name: 引用名
    public static func delete(_ name: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretsError.keychainError(status)
        }
        setCachedSecret(.missing, for: name)
    }
    
    /// 列出所有 secret 名称
    /// - Returns: 名称列表
    public static func list() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return []
        }
        
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw SecretsError.keychainError(status)
        }
        
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
    
    /// 检查 secret 是否存在
    /// - Parameter name: 引用名
    /// - Returns: 是否存在
    public static func exists(_ name: String) -> Bool {
        (try? get(name)) != nil
    }
    
    private static func cachedSecret(for name: String) -> CachedSecret? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[name]
    }
    
    private static func setCachedSecret(_ secret: CachedSecret, for name: String) {
        cacheLock.lock()
        cache[name] = secret
        cacheLock.unlock()
    }
    
    private enum CachedSecret {
        case value(String)
        case missing
    }
    
    // MARK: - 测试
    
    /// 测试 secret 是否有效（尝试读取）
    /// - Parameter name: 引用名
    /// - Returns: 测试结果
    public static func test(_ name: String) -> SecretTestResult {
        do {
            if let value = try get(name) {
                // 掩码显示
                let masked = String(repeating: "•", count: min(value.count, 8))
                return .ok(masked: masked)
            } else {
                return .notFound
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

// MARK: - 错误类型

public enum SecretsError: LocalizedError {
    case invalidValue
    case keychainError(OSStatus)
    
    public var errorDescription: String? {
        switch self {
        case .invalidValue:
            return "Invalid secret value"
        case .keychainError(let status):
            if let msg = SecCopyErrorMessageString(status, nil) {
                return "Keychain error: \(msg)"
            }
            return "Keychain error: \(status)"
        }
    }
}

// MARK: - 测试结果

public enum SecretTestResult {
    case ok(masked: String)
    case notFound
    case error(String)
}
