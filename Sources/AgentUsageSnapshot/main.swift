import Foundation
import AgentUsageCore

// Prints what the menu bar shows, from the shipped code and fixed sample
// data. Sample responses go through the real parsers, and every line comes
// from the real Output functions. No network, no Keychain, no window.
// The README images are built from this output.
//
//   swift run AgentUsageSnapshot

NSTimeZone.default = TimeZone(identifier: "UTC")!
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "UTC")!
calendar.locale = Locale(identifier: "en_US_POSIX")

func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}
func epoch(_ d: Date) -> String { String(Int(d.timeIntervalSince1970)) }

let now = at(10, 14, 14, 5)

// Sample Anthropic rate-limit headers and a sample Codex usage response.
let claudeHeaders: [AnyHashable: Any] = [
    "anthropic-ratelimit-unified-5h-utilization": "0.15",
    "anthropic-ratelimit-unified-5h-reset": epoch(at(10, 14, 19, 0)),
    "anthropic-ratelimit-unified-7d-utilization": "0.39",
    "anthropic-ratelimit-unified-7d-reset": epoch(at(10, 19, 9, 0)),
]
let codexJSON = """
{"plan_type":"plus","rate_limit":{
  "primary_window":{"used_percent":8,"limit_window_seconds":18000,"reset_at":\(epoch(at(10, 14, 21, 30)))},
  "secondary_window":{"used_percent":12,"limit_window_seconds":604800,"reset_at":\(epoch(at(10, 22, 9, 0)))}}}
"""

let claude = try ClaudeProvider.parseHeaders(claudeHeaders, now: now)
let codex = try CodexProvider.parseUsage(data: Data(codexJSON.utf8))
let snapshot = AgentSnapshot(results: [.claude: .success(claude), .codex: .success(codex)])

let label = Output.compact(snapshot)

// The menu bar label, then the dropdown rows in the order MenuBarController
// adds them. "---" marks a separator.
print("label: \(label)")
for usage in [claude, codex] {
    print("━━━ \(usage.provider.displayName) ━━━")
    for line in Output.windowLines(usage, now: now, calendar: calendar) { print(line) }
    print("---")
}
