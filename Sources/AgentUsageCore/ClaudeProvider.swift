import Foundation

public struct ClaudeProvider: UsageFetcher {
    public let id: Provider = .claude

    public init() {}

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let betaHeader = "oauth-2025-04-20"

    public enum Error: Swift.Error, CustomStringConvertible {
        case transport(Swift.Error)
        case httpStatus(Int, String)
        case unauthorized
        case missingHeaders

        public var description: String {
            switch self {
            case .transport(let e): return "Network error: \(e.localizedDescription)"
            case .httpStatus(let code, let body):
                let excerpt = body.prefix(200)
                return "HTTP \(code) from Anthropic. Body: \(excerpt)"
            case .unauthorized:
                return "Anthropic rejected the Claude token (401). Run `claude setup-token`, then `agent-usage --set-claude-token`."
            case .missingHeaders:
                return "Response missing rate-limit headers. API format may have changed."
            }
        }
    }

    public func fetch() async throws -> Usage {
        let creds = try ClaudeKeychain.readCredentials()
        return try await Self.fetchUsage(token: creds.accessToken)
    }

    public static func fetchUsage(token: String) async throws -> Usage {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

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
        if http.statusCode != 200 && http.statusCode != 429 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw Error.httpStatus(http.statusCode, body)
        }

        return try parseHeaders(http.allHeaderFields)
    }

    /// Builds Usage from the unified rate-limit headers. A window whose
    /// headers are absent or unparseable stays nil, never a fabricated 0%.
    public static func parseHeaders(_ headers: [AnyHashable: Any], now: Date = Date()) throws -> Usage {
        func window(_ name: String) -> (pct: Int, reset: Date)? {
            guard let pctStr = headers["anthropic-ratelimit-unified-\(name)-utilization"] as? String,
                  let resetStr = headers["anthropic-ratelimit-unified-\(name)-reset"] as? String,
                  let fraction = Double(pctStr),
                  let reset = TimeInterval(resetStr)
            else { return nil }
            return (Int((fraction * 100).rounded()), Date(timeIntervalSince1970: reset))
        }

        let session = window("5h")
        let weekly = window("7d")
        guard session != nil || weekly != nil else { throw Error.missingHeaders }

        return Usage(
            provider: .claude,
            sessionPct: session?.pct,
            sessionResetsAt: session?.reset,
            weeklyPct: weekly?.pct,
            weeklyResetsAt: weekly?.reset,
            fetchedAt: now
        )
    }
}
