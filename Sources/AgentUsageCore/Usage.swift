import Foundation

public struct Usage: Equatable, Codable, Sendable {
    public let provider: Provider
    /// Rate-limit windows are optional: a provider reports only the windows its
    /// plan actually exposes. Codex team plans, for example, have no 5-hour
    /// session window, only a weekly one, so `sessionPct` is nil there.
    public let sessionPct: Int?
    public let sessionResetsAt: Date?
    public let weeklyPct: Int?
    public let weeklyResetsAt: Date?
    public let fetchedAt: Date

    public init(
        provider: Provider,
        sessionPct: Int? = nil,
        sessionResetsAt: Date? = nil,
        weeklyPct: Int? = nil,
        weeklyResetsAt: Date? = nil,
        fetchedAt: Date
    ) {
        self.provider = provider
        self.sessionPct = sessionPct
        self.sessionResetsAt = sessionResetsAt
        self.weeklyPct = weeklyPct
        self.weeklyResetsAt = weeklyResetsAt
        self.fetchedAt = fetchedAt
    }

    /// Session usage at or above this takes over the compact label.
    public static let sessionAlertPct = 80

    /// The compact menu-bar figure: weekly by default, so both providers read
    /// the same window; the session window takes over once it is near its cap.
    public var labelPct: Int? {
        if let s = sessionPct, s >= Self.sessionAlertPct { return s }
        return weeklyPct ?? sessionPct
    }

    /// True when `labelPct` is showing the session window, not weekly.
    public var labelIsSession: Bool {
        guard let s = sessionPct else { return false }
        return s >= Self.sessionAlertPct || weeklyPct == nil
    }
}
