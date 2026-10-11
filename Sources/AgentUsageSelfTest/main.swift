import Foundation
import AgentUsageCore

// Zero-dependency self-test. Runs under Command Line Tools without full Xcode:
//   swift run AgentUsageSelfTest
// Exits non-zero if any check fails, so it can gate a build in CI or pre-commit.

var failures = 0

func check(_ name: String, _ condition: Bool) {
    if condition {
        print("  ok   \(name)")
    } else {
        print("  FAIL \(name)")
        failures += 1
    }
}

func data(_ s: String) -> Data { Data(s.utf8) }

// MARK: Codex parsing

// Team plan: single weekly window, secondary_window null. This is the shape
// that regressed the parser. Session must be nil so the UI omits it.
do {
    let json = """
    {"plan_type":"team","rate_limit":{
      "primary_window":{"used_percent":5,"limit_window_seconds":604800,"reset_at":1784519793},
      "secondary_window":null}}
    """
    let u = try CodexProvider.parseUsage(data: data(json))
    check("team: session nil", u.sessionPct == nil && u.sessionResetsAt == nil)
    check("team: weekly = 5", u.weeklyPct == 5)
    check("team: weekly reset parsed", u.weeklyResetsAt == Date(timeIntervalSince1970: 1784519793))
    check("team: label falls back to weekly (5)", u.labelPct == 5)
} catch {
    check("team: parses without throwing", false)
}

// Individual plan: 5h session (primary) + weekly (secondary), classified by
// duration not position.
do {
    let json = """
    {"plan_type":"plus","rate_limit":{
      "primary_window":{"used_percent":42,"limit_window_seconds":18000,"reset_at":1784500000},
      "secondary_window":{"used_percent":8,"limit_window_seconds":604800,"reset_at":1784519793}}}
    """
    let u = try CodexProvider.parseUsage(data: data(json))
    check("individual: session = 42", u.sessionPct == 42)
    check("individual: weekly = 8", u.weeklyPct == 8)
    check("individual: label shows weekly (8) below session alert", u.labelPct == 8)
} catch {
    check("individual: parses without throwing", false)
}

// A weekly-length window in the primary slot must map to weekly, never session.
do {
    let json = """
    {"rate_limit":{
      "primary_window":{"used_percent":30,"limit_window_seconds":604800,"reset_at":1784519793},
      "secondary_window":null}}
    """
    let u = try CodexProvider.parseUsage(data: data(json))
    check("primary weekly-length maps to weekly", u.sessionPct == nil && u.weeklyPct == 30)
} catch {
    check("primary weekly-length: parses", false)
}

// No rate_limit → throws (not a crash).
do {
    _ = try CodexProvider.parseUsage(data: data(#"{"plan_type":"team"}"#))
    check("missing rate_limit throws", false)
} catch {
    check("missing rate_limit throws", true)
}

// Both windows null → throws (nothing to show).
do {
    _ = try CodexProvider.parseUsage(data: data(#"{"rate_limit":{"primary_window":null,"secondary_window":null}}"#))
    check("both windows null throws", false)
} catch {
    check("both windows null throws", true)
}

// MARK: Output rendering

// Session-less plan: only the weekly row renders.
do {
    let u = Usage(provider: .codex, weeklyPct: 5,
                  weeklyResetsAt: Date(timeIntervalSince1970: 1784519793),
                  fetchedAt: Date(timeIntervalSince1970: 1783900000))
    let lines = Output.windowLines(u)
    check("session-less: one row", lines.count == 1)
    check("session-less: it's weekly", lines.first?.hasPrefix("Weekly:") == true)
}

// Both windows: two rows.
do {
    let u = Usage(provider: .claude, sessionPct: 55,
                  sessionResetsAt: Date(timeIntervalSince1970: 1783950000),
                  weeklyPct: 28,
                  weeklyResetsAt: Date(timeIntervalSince1970: 1784200000),
                  fetchedAt: Date(timeIntervalSince1970: 1783900000))
    check("both windows: two rows", Output.windowLines(u).count == 2)
}

// Compact label: weekly by default for both providers.
let t = Date(timeIntervalSince1970: 1783900000)
do {
    let claude = Usage(provider: .claude, sessionPct: 55, sessionResetsAt: t,
                       weeklyPct: 28, weeklyResetsAt: t, fetchedAt: t)
    let codex = Usage(provider: .codex, weeklyPct: 5, weeklyResetsAt: t, fetchedAt: t)
    let snap = AgentSnapshot(results: [.claude: .success(claude), .codex: .success(codex)])
    check("compact: weekly for both", Output.compact(snap) == "C:28% X:5%")
    check("exit code 0 when all succeed", snap.exitCode == 0)
}

// Compact label: a hot session takes over, marked "!".
do {
    let claude = Usage(provider: .claude, sessionPct: 85, sessionResetsAt: t,
                       weeklyPct: 28, weeklyResetsAt: t, fetchedAt: t)
    let snap = AgentSnapshot(results: [.claude: .success(claude)])
    check("compact: session >= 80 shows with !", Output.compact(snap) == "C:85%!")
}

// Compact label: a failed provider shows a warning, never vanishes.
do {
    let codex = Usage(provider: .codex, weeklyPct: 7, weeklyResetsAt: t, fetchedAt: t)
    let snap = AgentSnapshot(results: [
        .claude: .failure(ClaudeKeychain.Error.expired(t)),
        .codex: .success(codex),
    ])
    check("compact: failure shows warning", Output.compact(snap) == "C:⚠ X:7%")
    check("exit code 1 on credential failure", snap.exitCode == 1)
}

// Exit codes by error class; credential outranks format.
do {
    check("exit: claude 401 is credential (1)", ExitCode.forError(ClaudeProvider.Error.unauthorized) == 1)
    check("exit: codex 401 is credential (1)", ExitCode.forError(CodexProvider.Error.unauthorized) == 1)
    check("exit: missing headers is format (3)", ExitCode.forError(ClaudeProvider.Error.missingHeaders) == 3)
    check("exit: http 500 is network (2)", ExitCode.forError(ClaudeProvider.Error.httpStatus(500, "")) == 2)
    let snap = AgentSnapshot(results: [
        .claude: .failure(ClaudeProvider.Error.missingHeaders),
        .codex: .failure(CodexProvider.Error.unauthorized),
    ])
    check("exit: credential outranks format", snap.exitCode == 1)
}

// MARK: Claude

// Keychain JSON: expiresAt is epoch milliseconds.
do {
    let c = try ClaudeKeychain.parseCredentials(data(#"{"claudeAiOauth":{"accessToken":"x","expiresAt":1783900000000}}"#))
    check("keychain: expiresAt parsed from ms", c.expiresAt == t)
    let noExp = try ClaudeKeychain.parseCredentials(data(#"{"claudeAiOauth":{"accessToken":"x"}}"#))
    check("keychain: missing expiresAt is nil", noExp.expiresAt == nil)
} catch {
    check("keychain: parses", false)
}

// Pasted token: trimmed and prefix-checked; junk is refused.
check("token: trims whitespace", (try? ClaudeKeychain.normalizeToken("  sk-ant-oat01-abc\n")) == "sk-ant-oat01-abc")
check("token: rejects non-Claude text", (try? ClaudeKeychain.normalizeToken("hello")) == nil)
check("token: rejects inner whitespace", (try? ClaudeKeychain.normalizeToken("sk-ant-a b")) == nil)
check("exit: bad paste is credential (1)", ExitCode.forError(ClaudeKeychain.Error.badToken) == 1)

// Headers: both windows parsed.
do {
    let u = try ClaudeProvider.parseHeaders([
        "anthropic-ratelimit-unified-5h-utilization": "0.15",
        "anthropic-ratelimit-unified-5h-reset": "1783950000",
        "anthropic-ratelimit-unified-7d-utilization": "0.39",
        "anthropic-ratelimit-unified-7d-reset": "1784200000",
    ], now: t)
    check("claude headers: session 15, weekly 39", u.sessionPct == 15 && u.weeklyPct == 39)
} catch {
    check("claude headers: parse", false)
}

// Headers: an unparseable window is nil, not a fabricated 0%.
do {
    let u = try ClaudeProvider.parseHeaders([
        "anthropic-ratelimit-unified-5h-utilization": "garbage",
        "anthropic-ratelimit-unified-5h-reset": "1783950000",
        "anthropic-ratelimit-unified-7d-utilization": "0.39",
        "anthropic-ratelimit-unified-7d-reset": "1784200000",
    ], now: t)
    check("claude headers: bad session is nil, not 0", u.sessionPct == nil && u.weeklyPct == 39)
} catch {
    check("claude headers: partial parse", false)
}

// Headers: none present → throws.
do {
    _ = try ClaudeProvider.parseHeaders([:], now: t)
    check("claude headers: none throws", false)
} catch {
    check("claude headers: none throws", true)
}

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) FAILED.")
exit(failures == 0 ? 0 : 1)
