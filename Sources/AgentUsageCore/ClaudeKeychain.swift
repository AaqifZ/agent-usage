import Foundation
import Security

/// Claude token sources, in order of preference:
///
/// 1. agent-usage's own Keychain item, holding a long-lived inference-only
///    token from `claude setup-token`. Nothing else uses this token, so it
///    never goes stale under us and needs no refresh.
/// 2. Claude Code's Keychain item (fallback). Only the terminal `claude` CLI
///    refreshes it (the desktop app does not), so it can be expired.
public enum ClaudeKeychain {

    /// Claude Code's item. Read only, never written.
    private static let claudeCodeService = "Claude Code-credentials"
    /// agent-usage's own item. Written only by `agent-usage --set-claude-token`.
    public static let dedicatedService = "agent-usage-claude-token"
    private static let dedicatedAccount = "agent-usage"

    public enum Source: Sendable { case dedicated, claudeCode }

    public struct Credentials: Sendable {
        public let accessToken: String
        /// When the access token expires, if Claude Code recorded it.
        public let expiresAt: Date?
        public let source: Source
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case notFound
        case badFormat
        case osStatus(OSStatus)
        case expired(Date)
        case badToken

        public var description: String {
            switch self {
            case .notFound:
                return "No Claude token in Keychain. Run `claude setup-token`, then `agent-usage --set-claude-token`."
            case .badFormat:
                return "Claude Code credentials in Keychain have unexpected format."
            case .osStatus(let status):
                return "Keychain error (OSStatus \(status)). Approve the Keychain prompt if one appears."
            case .expired(let date):
                let f = DateFormatter()
                f.dateFormat = "MMM d, HH:mm"
                return "Claude Code's Keychain token expired \(f.string(from: date)). For a token that lasts, run `claude setup-token`, then `agent-usage --set-claude-token`."
            case .badToken:
                return "That does not look like a Claude OAuth token (expected sk-ant-…)."
            }
        }
    }

    /// Reads the best available token and refuses an expired one, so a stale
    /// Keychain entry surfaces as a clear credential error instead of a 401.
    public static func readCredentials(now: Date = Date()) throws -> Credentials {
        if let token = try readDedicated() {
            return Credentials(accessToken: token, expiresAt: nil, source: .dedicated)
        }
        let creds = try parseCredentials(try readItem(service: claudeCodeService, account: nil))
        if let expiresAt = creds.expiresAt, expiresAt <= now {
            throw Error.expired(expiresAt)
        }
        return creds
    }

    /// Stores the dedicated token, replacing any earlier one. Device-only, so
    /// it is never synced to iCloud Keychain or restored to another Mac.
    public static func saveDedicated(_ token: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: dedicatedService,
            kSecAttrAccount as String: dedicatedAccount,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrLabel as String] = "agent-usage Claude token"
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Error.osStatus(status) }
    }

    /// Trims pasted input and checks it looks like a Claude OAuth token.
    public static func normalizeToken(_ raw: String) throws -> String {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.hasPrefix("sk-ant-"), !token.contains(where: \.isWhitespace) else {
            throw Error.badToken
        }
        return token
    }

    /// Parses Claude Code's Keychain JSON. `expiresAt` is epoch milliseconds.
    public static func parseCredentials(_ data: Data) throws -> Credentials {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = raw["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else {
            throw Error.badFormat
        }
        let expiresAt = (oauth["expiresAt"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return Credentials(accessToken: token, expiresAt: expiresAt, source: .claudeCode)
    }

    // MARK: - Keychain

    private static func readDedicated() throws -> String? {
        do {
            let data = try readItem(service: dedicatedService, account: dedicatedAccount)
            return String(data: data, encoding: .utf8)
        } catch Error.notFound {
            return nil
        }
    }

    private static func readItem(service: String, account: String?) throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let account { query[kSecAttrAccount as String] = account }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { throw Error.notFound }
            throw Error.osStatus(status)
        }
        guard let data = item as? Data else { throw Error.badFormat }
        return data
    }
}
