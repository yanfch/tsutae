import CryptoKit
import Foundation
import Security

public struct ServerClientCreationResult: Sendable {
    public let client: Config.ServerClientConfig
    public let token: String

    public init(client: Config.ServerClientConfig, token: String) {
        self.client = client
        self.token = token
    }
}

public enum ServerClientAuthError: LocalizedError {
    case missingToken
    case invalidToken
    case disabledClient(String)
    case insufficientScope(String, Config.ServerClientScope)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Missing bearer token."
        case .invalidToken:
            return "Invalid bearer token."
        case .disabledClient(let name):
            return "Client is disabled: \(name)."
        case .insufficientScope(let name, let scope):
            return "Client \(name) is missing scope: \(scope.rawValue)."
        }
    }
}

public enum ServerClientRegistry {
    public static func createClient(
        name: String,
        scopes: [Config.ServerClientScope] = Config.ServerClientScope.defaultScopes
    ) -> ServerClientCreationResult {
        let token = generateToken()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = Config.ServerClientConfig(
            id: makeClientID(),
            name: trimmedName.isEmpty ? "Untitled Client" : trimmedName,
            tokenHash: hash(token),
            scopes: scopes,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        return ServerClientCreationResult(client: client, token: token)
    }

    public static func regenerateToken(for client: Config.ServerClientConfig) -> ServerClientCreationResult {
        let token = generateToken()
        var updated = client
        updated.tokenHash = hash(token)
        return ServerClientCreationResult(client: updated, token: token)
    }

    public static func authenticate(
        token: String?,
        requiredScope: Config.ServerClientScope?,
        server: Config.ServerConfig
    ) throws -> Config.ServerClientConfig? {
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), token.isEmpty == false else {
            if server.requireToken {
                throw ServerClientAuthError.missingToken
            }
            return nil
        }

        let hashed = hash(token)
        guard let client = server.clients.first(where: { constantTimeEquals($0.tokenHash, hashed) }) else {
            throw ServerClientAuthError.invalidToken
        }
        guard client.enabled else {
            throw ServerClientAuthError.disabledClient(client.name)
        }
        if let requiredScope, client.hasScope(requiredScope) == false {
            throw ServerClientAuthError.insufficientScope(client.name, requiredScope)
        }
        return client
    }

    public static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func generateToken() -> String {
        let bytes = randomBytes(count: 32)
        return "tsutae_" + hexadecimal(bytes)
    }

    private static func makeClientID() -> String {
        "client_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private static func randomBytes(count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        if status == errSecSuccess {
            return bytes
        }
        return Array(UUID().uuidString.utf8).prefix(count).map { $0 }
    }

    private static func hexadecimal(_ bytes: [UInt8]) -> String {
        bytes
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }

        var diff: UInt8 = 0
        for index in left.indices {
            diff |= left[index] ^ right[index]
        }
        return diff == 0
    }
}
