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

extension TimingDriver.LocationState {
    /// What the selected-driver detail says about the position: never "located" for old data.
    public func label(for driver: TimingDriver, at now: Date) -> String {
        switch self {
        case .located: return "Located"
        case .unavailable: return "No position data"
        case .stale:
            guard let timestamp = driver.location?.timestamp else { return "Stale" }
            return "Stale · \(max(0, Int(now.timeIntervalSince(timestamp)))) s old"
        }
    }
}

/// How loudly a calendar weekend is drawn. Only the next race is a hero; the past is quiet.
public enum WeekendEmphasis: Sendable, Equatable {
    case next, upcoming, past

    public init(race: RaceWeekend, nextRound: Int?, now: Date) {
        if race.isPast(at: now) { self = .past }
        else if race.round == nextRound { self = .next }
        else { self = .upcoming }
    }

    /// Only the hero shows its sessions before the user asks.
    public var startsExpanded: Bool { self == .next }
    public var badge: String {
        switch self {
        case .next: "NEXT RACE"
        case .upcoming: "UPCOMING"
        case .past: "PAST"
        }
    }
}

extension RaceWeekend {
    /// When the race itself starts, if the calendar has published a time for it.
    public var raceStart: Date? { sessions.first { $0.name == "Race" }?.startDate }

    /// "in 3d 4h" until lights out, or "Time TBC" when the start is not published.
    public func countdownText(now: Date) -> String {
        raceStart.map { Countdown.text(until: $0, now: now) } ?? "Time TBC"
    }
}

extension RaceSchedule {
    /// The single caption under the filter: the zone every time is shown in, and where the data is from.
    public func timesCaption(timeZoneIdentifier: String) -> String {
        mode == "demo"
            ? "Times in \(timeZoneIdentifier) · DEMO · \(source)"
            : "Times in \(timeZoneIdentifier) · \(source)"
    }
}

/// Where to put the selected driver's code label so it never covers the marker.
public enum MarkerLabelPlacement {
    public struct Rect: Equatable, Sendable {
        public var x: Double, y: Double, width: Double, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
        public var maxX: Double { x + width }
        public var maxY: Double { y + height }
    }

    /// The label's frame: centred above the marker, below it when there is no room above,
    /// and kept inside `bounds` sideways. `gap` is the clear space between marker and label.
    public static func frame(markerX: Double, markerY: Double, markerRadius: Double,
                             labelWidth: Double, labelHeight: Double,
                             bounds: Rect, gap: Double = 4) -> Rect {
        let x = min(max(markerX - labelWidth / 2, bounds.x), max(bounds.x, bounds.maxX - labelWidth))
        let above = markerY - markerRadius - gap - labelHeight
        if above >= bounds.y { return Rect(x: x, y: above, width: labelWidth, height: labelHeight) }
        return Rect(x: x, y: markerY + markerRadius + gap, width: labelWidth, height: labelHeight)
    }
}
