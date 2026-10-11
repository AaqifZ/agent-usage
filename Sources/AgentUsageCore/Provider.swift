import Foundation

public enum Provider: String, Codable, Sendable, CaseIterable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex:  return "Codex"
        }
    }

    public var shortCode: String {
        switch self {
        case .claude: return "C"
        case .codex:  return "X"
        }
    }
}

public protocol UsageFetcher: Sendable {
    var id: Provider { get }
    func fetch() async throws -> Usage
}

/// CLI exit codes: 1 credential, 2 network / API, 3 unexpected format.
public enum ExitCode {
    public static func forError(_ error: Swift.Error) -> Int32 {
        switch error {
        case is ClaudeKeychain.Error, is CodexAuthFile.Error,
             ClaudeProvider.Error.unauthorized, CodexProvider.Error.unauthorized:
            return 1
        case ClaudeProvider.Error.missingHeaders, CodexProvider.Error.badResponse:
            return 3
        default:
            return 2
        }
    }
}

public struct AgentSnapshot: Sendable {
    public let results: [Provider: Result<Usage, Swift.Error>]

    public init(results: [Provider: Result<Usage, Swift.Error>]) {
        self.results = results
    }

    public var successes: [Usage] {
        Provider.allCases.compactMap { p in
            if case .success(let u) = results[p] { return u } else { return nil }
        }
    }

    /// The most severe exit code across failed providers, or 0 if none failed.
    /// Credential errors (1) outrank format (3) and network (2) errors, since
    /// they need the user to act.
    public var exitCode: Int32 {
        let codes = results.values.compactMap { r -> Int32? in
            if case .failure(let e) = r { return ExitCode.forError(e) } else { return nil }
        }
        if codes.contains(1) { return 1 }
        return codes.max() ?? 0
    }
}
