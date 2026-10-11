import Foundation
import AgentUsageCore

// MARK: - CLI entry

let args = Array(CommandLine.arguments.dropFirst())

if args.contains("--help") || args.contains("-h") {
    print("""
    agent-usage — least-access usage tracker for Claude and Codex

    USAGE
        agent-usage                      Print usage for all signed-in providers
        agent-usage --provider claude    Claude only
        agent-usage --provider codex     Codex only
        agent-usage --json               Machine-readable JSON
        agent-usage --watch              Poll every 60s, print on change
        agent-usage --set-claude-token   Store a token from `claude setup-token`
                                         (hidden paste, or pipe it on stdin)
        agent-usage --help               Show this help

    BEHAVIOR
        Claude: reads agent-usage's own Keychain token (service:
                "agent-usage-claude-token", set with --set-claude-token),
                else Claude Code's ("Claude Code-credentials"). Hits
                api.anthropic.com, reports rate-limit percentages from
                response headers. Never refreshes a token.

        Codex:  reads ~/.codex/auth.json (mode 0600 required, read-only),
                hits chatgpt.com/backend-api/wham/usage, reports the windows
                the plan exposes. Never refreshes the token: run `codex` once
                if it has expired.

    EXIT CODES (any selected provider failing makes the exit non-zero)
        0  success
        1  credential error (missing, unreadable, or expired tokens)
        2  network / API error
        3  unexpected response format
    """)
    exit(0)
}

// MARK: - --set-claude-token

if args.contains("--set-claude-token") {
    var raw = ""
    if isatty(STDIN_FILENO) != 0 {
        var buf = [CChar](repeating: 0, count: 1024)
        if let p = readpassphrase("Paste the token from `claude setup-token` (hidden): ", &buf, buf.count, 0) {
            raw = String(cString: p)
        }
        buf.withUnsafeMutableBytes { _ = memset($0.baseAddress, 0, $0.count) }
    } else {
        raw = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
    Task {
        do {
            // Validate against the API before saving, so a bad paste never
            // replaces a working token.
            let token = try ClaudeKeychain.normalizeToken(raw)
            let usage = try await ClaudeProvider.fetchUsage(token: token)
            try ClaudeKeychain.saveDedicated(token)
            print("Saved to Keychain (\(ClaudeKeychain.dedicatedService)).\n")
            print(Output.text([usage]))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Not saved: \(error)\n".utf8))
            exit(ExitCode.forError(error))
        }
    }
    dispatchMain()
}

func providerFromArgs() -> [Provider] {
    if let idx = args.firstIndex(of: "--provider"), idx + 1 < args.count {
        let v = args[idx + 1].lowercased()
        switch v {
        case "claude": return [.claude]
        case "codex":  return [.codex]
        case "all":    return Provider.allCases
        default:
            FileHandle.standardError.write(Data("error: --provider must be claude|codex|all\n".utf8))
            exit(1)
        }
    }
    return Provider.allCases
}

let providers = providerFromArgs()
let outputJSON = args.contains("--json")
let watchMode  = args.contains("--watch")

@Sendable
func fetchAndPrint(previous: [Usage]) async -> AgentSnapshot {
    let snapshot = await Fetcher.fetchAll(providers: providers)
    let usages = snapshot.successes

    if !previous.isEmpty
        && previous.count == usages.count
        && zip(previous, usages).allSatisfy({ $0.sessionPct == $1.sessionPct && $0.weeklyPct == $1.weeklyPct }) {
        return snapshot
    }

    // Print any errors (one per failed provider) to stderr so stdout stays parseable.
    for p in providers {
        if case .failure(let err) = snapshot.results[p] {
            FileHandle.standardError.write(Data("\(p.displayName) error: \(String(describing: err))\n".utf8))
        }
    }

    if outputJSON {
        do {
            print(try Output.json(usages))
        } catch {
            FileHandle.standardError.write(Data("json error: \(error.localizedDescription)\n".utf8))
            exit(3)
        }
    } else {
        print(Output.text(usages))
    }
    return snapshot
}

if watchMode {
    Task {
        var previous: [Usage] = []
        while true {
            previous = await fetchAndPrint(previous: previous).successes
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
    }
    dispatchMain()
} else {
    Task {
        let snapshot = await fetchAndPrint(previous: [])
        // Non-zero if ANY selected provider failed, so scripts notice a half outage.
        exit(snapshot.exitCode)
    }
    dispatchMain()
}
