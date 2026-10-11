import Foundation

public struct CodexProvider: UsageFetcher {
    public let id: Provider = .codex

    public init() {}

    /// Hardcoded URL. The ONLY Codex-related endpoint this tool hits.
    /// Token refresh is left to the `codex` CLI: refreshing here would rotate
    /// the refresh token underneath it and could log it out.
    private static let usageEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    public enum Error: Swift.Error, CustomStringConvertible {
        case transport(Swift.Error)
        case httpStatus(Int, String)
        case badResponse
        case unauthorized

        public var description: String {
            switch self {
            case .transport(let e): return "Network error: \(e.localizedDescription)"
            case .httpStatus(let code, let body):
                let excerpt = body.prefix(200)
                return "HTTP \(code) from Codex. Body: \(excerpt)"
            case .badResponse:
                return "Codex usage response missing expected fields. API format may have changed."
            case .unauthorized:
                return "Codex token rejected (401). Run `codex` once to refresh it, or `codex login`."
            }
        }
    }

    public func fetch() async throws -> Usage {
        try await Self.fetchUsage(authFile: CodexAuthFile.read())
    }

    // MARK: - Usage fetch

    public static func fetchUsage(authFile: CodexAuthFile.AuthFile) async throws -> Usage {
        var req = URLRequest(url: usageEndpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(authFile.tokens.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("agent-usage/0.1.0", forHTTPHeaderField: "User-Agent")
        if let accountId = authFile.tokens.accountId {
            req.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw Error.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw Error.httpStatus(0, String(data: data, encoding: .utf8) ?? "")
        }
        if http.statusCode == 401 { throw Error.unauthorized }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw Error.httpStatus(http.statusCode, body)
        }

        do {
            return try parseUsage(data: data)
        } catch {
            // Debug path: on a parse failure with AGENT_USAGE_DEBUG set, print the
            // first 2,000 characters of the raw response to stderr.
            if ProcessInfo.processInfo.environment["AGENT_USAGE_DEBUG"] != nil {
                let body = String(data: data, encoding: .utf8) ?? ""
                FileHandle.standardError.write(Data("codex debug body: \(body.prefix(2000))\n".utf8))
            }
            throw error
        }
    }

    public static func parseUsage(data: Data) throws -> Usage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimit = root["rate_limit"] as? [String: Any]
        else {
            throw Error.badResponse
        }

        // Windows are keyed positionally by the API (primary/secondary), but the
        // duration each represents varies by plan: on individual plans the
        // primary window is the ~5h session and the secondary is the weekly; on
        // team plans there is only a single weekly window (primary), with
        // secondary_window null. Either window may be absent, so classify each
        // present window by its own limit_window_seconds instead of by position.
        let windows = [rateLimit["primary_window"], rateLimit["secondary_window"]]
            .compactMap { $0 as? [String: Any] }
        guard !windows.isEmpty else { throw Error.badResponse }

        // Threshold splitting a session window (~5h) from a weekly window (7d).
        let sessionMaxSeconds: Double = 24 * 60 * 60

        // Windows the plan doesn't expose stay nil, never fabricated. A team
        // plan with only a weekly window yields sessionPct == nil, so the UI can
        // omit the session line entirely rather than show a phantom 0%.
        var sessionPct: Int?
        var weeklyPct: Int?
        var sessionReset: Date?
        var weeklyReset: Date?

        for window in windows {
            let pct = intPercent(window["used_percent"])
            let reset = dateFrom(window["reset_at"])
            let durationSeconds = (window["limit_window_seconds"] as? NSNumber)?.doubleValue
            // An unlabeled window defaults to weekly, the safer assumption for
            // surfacing quota, and it matches the team-plan single-window case.
            let isSession = durationSeconds.map { $0 <= sessionMaxSeconds } ?? false
            if isSession {
                sessionPct = pct; sessionReset = reset
            } else {
                weeklyPct = pct; weeklyReset = reset
            }
        }

        return Usage(
            provider: .codex,
            sessionPct: sessionPct,
            sessionResetsAt: sessionReset,
            weeklyPct: weeklyPct,
            weeklyResetsAt: weeklyReset,
            fetchedAt: Date()
        )
    }

    private static func intPercent(_ any: Any?) -> Int {
        if let n = any as? NSNumber { return Int(n.doubleValue.rounded()) }
        if let s = any as? String, let d = Double(s) { return Int(d.rounded()) }
        return 0
    }

    private static func dateFrom(_ any: Any?) -> Date {
        if let n = any as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
        if let s = any as? String {
            if let ts = TimeInterval(s) { return Date(timeIntervalSince1970: ts) }
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: s) { return d }
        }
        return Date()
    }
}
