import Foundation

/// "in 3d 4h" style countdowns for the next race. Units are truncated, never rounded up,
/// so the text can only ever err on the side of "sooner than you think" by under a unit.
public enum Countdown {
    public static func text(until target: Date, now: Date) -> String {
        let remaining = target.timeIntervalSince(now)
        guard remaining > 0 else { return "Started" }
        let minutes = Int(remaining / 60)
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let mins = minutes % 60
        if days > 0 { return hours > 0 ? "in \(days)d \(hours)h" : "in \(days)d" }
        if hours > 0 { return mins > 0 ? "in \(hours)h \(mins)m" : "in \(hours)h" }
        if mins > 0 { return "in \(mins)m" }
        return "in under a minute"
    }
}

/// One column of the timing tower.
public enum TimingColumn: Sendable, Equatable {
    case position, driver, team, gap, lastLap, tyre
}

/// How much of the tower fits. Views try `wide`, then `standard`, then `compact`, and
/// only scroll horizontally when even `compact` does not fit.
public enum TimingLayout: CaseIterable, Sendable {
    case wide, standard, compact

    public var columns: [TimingColumn] {
        switch self {
        case .wide: [.position, .driver, .team, .gap, .lastLap, .tyre]
        case .standard: [.position, .driver, .gap, .lastLap, .tyre]
        case .compact: [.position, .driver, .gap, .tyre]
        }
    }

    public func shows(_ column: TimingColumn) -> Bool { columns.contains(column) }
}

extension TimingDriver {
    public var isLeader: Bool { position == 1 }

    /// The GAP column: the leader has no gap to show, so says so.
    public var gapText: String {
        if isLeader { return "LEADER" }
        let trimmed = gap?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "—" : trimmed
    }

    public enum LocationState: Sendable, Equatable { case located, stale, unavailable }

    public func locationState(at now: Date) -> LocationState {
        guard let location else { return .unavailable }
        return location.isStale(at: now) ? .stale : .located
    }
}

extension TimingSnapshot {
    /// "3 of 4 drivers located", plus " · 1 stale" when any known position is old.
    public func locationSummary(at now: Date) -> String {
        let located = drivers.filter { $0.location != nil }.count
        let stale = drivers.filter { $0.locationState(at: now) == .stale }.count
        var text = "\(located) of \(drivers.count) \(drivers.count == 1 ? "driver" : "drivers") located"
        if stale > 0 { text += " · \(stale) stale" }
        return text
    }
}
