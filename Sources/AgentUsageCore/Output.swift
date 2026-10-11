import Foundation

public enum Output {

    /// Human-readable multi-line text. One section per provider.
    public static func text(_ usages: [Usage], now: Date = Date(), calendar: Calendar = .current) -> String {
        if usages.isEmpty { return "No providers signed in." }
        return usages.map { u in section(u, now: now, calendar: calendar) }.joined(separator: "\n\n")
    }

    public static func section(_ u: Usage, now: Date = Date(), calendar: Calendar = .current) -> String {
        let body = windowLines(u, now: now, calendar: calendar).joined(separator: "\n")
        return "━━━ \(u.provider.displayName) ━━━\n\(body)"
    }

    /// Single-line human text for one provider. Used in the menu bar tooltip.
    public static func line(_ u: Usage, now: Date = Date(), calendar: Calendar = .current) -> String {
        let windows = windowLines(u, now: now, calendar: calendar).joined(separator: "  |  ")
        return "\(u.provider.displayName) — \(windows)"
    }

    /// The window rows a provider actually exposes, in display order. A plan
    /// without a session window (e.g. Codex team) simply omits that line.
    public static func windowLines(_ u: Usage, now: Date = Date(), calendar: Calendar = .current) -> [String] {
        var lines: [String] = []
        if let usage = sessionLine(u, now: now, calendar: calendar) { lines.append(usage) }
        if let usage = weeklyLine(u, now: now, calendar: calendar) { lines.append(usage) }
        if lines.isEmpty { lines.append("No usage data.") }
        return lines
    }

    /// Compact menu bar label. "C:39% X:7%" shows weekly usage; a session at
    /// or above `Usage.sessionAlertPct` shows instead, marked "!" ("C:85%!").
    /// A provider that failed shows "⚠", never silently dropped.
    public static func compact(_ snapshot: AgentSnapshot) -> String {
        let parts: [String] = Provider.allCases.compactMap { p in
            switch snapshot.results[p] {
            case .success(let u):
                guard let pct = u.labelPct else { return "\(p.shortCode):—" }
                let mark = u.labelIsSession && u.weeklyPct != nil ? "!" : ""
                return "\(p.shortCode):\(pct)%\(mark)"
            case .failure:
                return "\(p.shortCode):⚠"
            case .none:
                return nil
            }
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }

    /// JSON output. Stable schema for scripting.
    /// { "providers": { "claude": {...}, "codex": {...} } }
    public static func json(_ usages: [Usage]) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]

        var dict: [String: Usage] = [:]
        for u in usages { dict[u.provider.rawValue] = u }

        let payload = ["providers": dict]
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Formatted session line, or nil if the plan exposes no session window.
    /// "Session: 15% (resets 19:00)"
    public static func sessionLine(_ u: Usage, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let pct = u.sessionPct, let reset = u.sessionResetsAt else { return nil }
        let r = formatReset(reset, now: now, calendar: calendar, style: .sameDayTime)
        return "Session: \(pct)% (resets \(r))"
    }

    /// Formatted weekly line, or nil if the plan exposes no weekly window.
    /// "Weekly:  39% (resets Apr 19)"
    public static func weeklyLine(_ u: Usage, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let pct = u.weeklyPct, let reset = u.weeklyResetsAt else { return nil }
        let r = formatReset(reset, now: now, calendar: calendar, style: .dateOnly)
        return "Weekly:  \(pct)% (resets \(r))"
    }

    // MARK: - Helpers

    public enum ResetStyle { case sameDayTime, dateOnly }

    public static func formatReset(_ reset: Date, now: Date, calendar: Calendar, style: ResetStyle) -> String {
        let df = DateFormatter()
        df.calendar = calendar
        df.locale = Locale.current
        switch style {
        case .sameDayTime:
            if calendar.isDate(reset, inSameDayAs: now) {
                df.dateFormat = "HH:mm"
            } else {
                df.dateFormat = "MMM d, HH:mm"
            }
        case .dateOnly:
            df.dateFormat = "MMM d"
        }
        return df.string(from: reset)
    }
}
