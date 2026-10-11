import Foundation

/// Reads ~/.codex/auth.json (or $CODEX_HOME/auth.json). Read-only: the
/// `codex` CLI owns this file and its token refresh.
///
/// HARDCODED to this single file path. No other files are read by this
/// module. File mode is enforced at 0600. If the file is world- or
/// group-readable, we refuse to read it and tell the user to tighten perms.
public enum CodexAuthFile {

    /// Only the fields the usage request needs. The refresh and id tokens are
    /// never decoded or kept.
    public struct Tokens: Decodable, Sendable {
        public var accessToken: String
        public var accountId: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountId = "account_id"
        }
    }

    public struct AuthFile: Decodable, Sendable {
        public var tokens: Tokens
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case notFound(String)
        case badFormat
        case insecurePermissions(mode: UInt16, path: String)

        public var description: String {
            switch self {
            case .notFound(let path):
                return "Codex auth not found at \(path). Sign in with 'codex login' first."
            case .badFormat:
                return "Codex auth.json has unexpected format."
            case .insecurePermissions(let mode, let path):
                return String(format: "Codex auth.json at %@ has insecure mode %03o. Run: chmod 600 %@", path, mode, path)
            }
        }
    }

    /// Resolve ~/.codex/auth.json (or $CODEX_HOME/auth.json).
    public static func path() -> String {
        let env = ProcessInfo.processInfo.environment
        let home = env["CODEX_HOME"] ?? (env["HOME"].map { "\($0)/.codex" } ?? "")
        return "\(home)/auth.json"
    }

    public static func read() throws -> AuthFile {
        let p = path()
        let fm = FileManager.default
        guard fm.fileExists(atPath: p) else { throw Error.notFound(p) }

        let attrs = try fm.attributesOfItem(atPath: p)
        if let perm = attrs[.posixPermissions] as? NSNumber {
            let mode = perm.uint16Value & 0o777
            // Reject if group or world has any access.
            if mode & 0o077 != 0 {
                throw Error.insecurePermissions(mode: mode, path: p)
            }
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: p))

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(AuthFile.self, from: data)
        } catch {
            throw Error.badFormat
        }
    }
}
