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

/// "45 s", "38 min", "1 h 12 min", "1 d 2 h": how long ago something happened, in the
/// largest units that read naturally. Rounds to the nearest minute (hour once past a day),
/// so a value is never shown as "60 min" or "24 h".
public enum DurationText {
    public static func compact(seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds.rounded())) : 0
        if total < 60 { return "\(total) s" }
        let minutes = (total + 30) / 60
        if minutes < 60 { return "\(minutes) min" }
        if minutes < 1440 {
            let hours = minutes / 60, rest = minutes % 60
            return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
        }
        let hours = (total + 1800) / 3600
        let days = hours / 24, rest = hours % 24
        return rest == 0 ? "\(days) d" : "\(days) d \(rest) h"
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

    /// Only the widest layout asks for room for the whole team name; below it the name truncates.
    public var showsFullTeamName: Bool { self == .wide }

    /// The columns to draw. When no gap is worth showing the GAP column is dropped, LAST LAP
    /// (now the only timing figure) is kept at every width instead of being the first thing to go,
    /// and the team takes the room GAP left (truncating) at every layout but the narrowest.
    public func columns(showingGap: Bool) -> [TimingColumn] {
        if showingGap { return columns }
        var result = columns.filter { $0 != .gap }
        if !result.contains(.lastLap), let tyre = result.firstIndex(of: .tyre) { result.insert(.lastLap, at: tyre) }
        if self == .standard, let lastLap = result.firstIndex(of: .lastLap) { result.insert(.team, at: lastLap) }
        return result
    }
}

extension Collection where Element == TimingDriver {
    /// A GAP column needs gaps to compare: two drivers with one, or, on a board of two, the one trailing
    /// driver (the leader has none to show). Practice and qualifying report none (or a stray one among
    /// many drivers), and a column of dashes is noise, so it is dropped there.
    public var hasUsableGaps: Bool {
        let gapped = filter { !($0.gap?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }.count
        let trailing = Swift.max(count - 1, 1)
        return gapped >= Swift.min(2, trailing)
    }
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
            return "Stale · \(DurationText.compact(seconds: now.timeIntervalSince(timestamp))) old"
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
    /// The round and country eyebrow as lines of text: one line "Round 20 · Brazil", or, when `stacked`
    /// (accessibility text sizes), "Round 20" over "Brazil" with no separator. A separator can then
    /// never wrap onto the start of a line.
    public func roundLines(stacked: Bool) -> [String] {
        stacked ? ["Round \(round)", country] : ["Round \(round) · \(country)"]
    }

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

// MARK: App sections

/// The two top-level screens. The feed status describes the live timing connection, so only
/// that screen shows it; the calendar has its own demo / saved-schedule labelling.
public enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case live = "Live timing", schedule = "Schedule"
    public var id: Self { self }
    public var showsFeedStatus: Bool { self == .live }
}

// MARK: Calendar

public enum ScheduleFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All", upcoming = "Upcoming", past = "Past"
    public var id: Self { self }

    public func includes(_ race: RaceWeekend, at now: Date) -> Bool {
        switch self {
        case .all: true
        case .upcoming: !race.isPast(at: now)
        case .past: race.isPast(at: now)
        }
    }
}

/// Where the calendar list should be scrolled to when it opens.
public enum CalendarFocus: Equatable, Sendable {
    /// The next race, as the hero.
    case nextRace(round: Int)
    /// Nothing is left this season: show the last race, with a "Season complete" note.
    case seasonComplete(lastRound: Int)
    /// Nothing to focus; stay at the top.
    case top
}

extension RaceSchedule {
    /// Open on what is coming: Upcoming while the season has races left, All once it is over.
    public func defaultFilter(at now: Date) -> ScheduleFilter {
        nextRace(at: now) == nil ? .all : .upcoming
    }

    public func races(matching filter: ScheduleFilter, at now: Date) -> [RaceWeekend] {
        races.filter { filter.includes($0, at: now) }
    }

    public func calendarFocus(for filter: ScheduleFilter, at now: Date) -> CalendarFocus {
        let visible = races(matching: filter, at: now)
        guard !visible.isEmpty else { return .top }
        if let next = nextRace(at: now) {
            return visible.contains { $0.round == next.round } ? .nextRace(round: next.round) : .top
        }
        // `visible` is non-empty, so `max` exists.
        return .seasonComplete(lastRound: visible.map(\.round).max() ?? 0)
    }
}

extension RaceWeekend {
    /// "Mar 6–8", "Jun 28 – Jul 1", or "Mar 6" for a one-day weekend. No weekday names, so it
    /// always fits on one line. Days are taken in `timeZone`, like every other time in the app.
    public func dateRange(timeZone: TimeZone = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) -> String? {
        let days = sessions.compactMap { $0.startDate ?? $0.calendarDate(timeZone: timeZone) }
        guard let first = days.min(), let last = days.max() else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let a = calendar.dateComponents([.year, .month, .day], from: first)
        let b = calendar.dateComponents([.year, .month, .day], from: last)

        func format(_ template: String, _ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter.string(from: date)
        }

        if a == b { return format("MMMd", first) }
        guard a.year == b.year, a.month == b.month, let startDay = a.day, let endDay = b.day else {
            return "\(format("MMMd", first)) – \(format("MMMd", last))"
        }
        // Month-first locales read "Mar 6–8"; day-first ones read "6–8 Mar".
        let pattern = DateFormatter.dateFormat(fromTemplate: "MMMd", options: 0, locale: locale) ?? "MMM d"
        let monthFirst = (pattern.firstIndex(of: "M") ?? pattern.endIndex) < (pattern.firstIndex(of: "d") ?? pattern.endIndex)
        let month = format("MMM", first)
        return monthFirst ? "\(month) \(startDay)–\(endDay)" : "\(startDay)–\(endDay) \(month)"
    }
}

// MARK: Track map

extension TimingSnapshot {
    /// True when at least one driver has a position and every known position is stale.
    /// Stale positions are all the same old spot, so drawing them only piles markers up.
    public func allPositionsStale(at now: Date) -> Bool {
        let locations = drivers.compactMap(\.location)
        return !locations.isEmpty && locations.allSatisfy { $0.isStale(at: now) }
    }

    /// The caption drawn over the empty track when no position is worth plotting; nil otherwise.
    public func positionsNotLiveCaption(at now: Date, connected: Bool) -> String? {
        guard allPositionsStale(at: now) else { return nil }
        if !connected || upstream != "connected" { return "Disconnected · positions not live" }
        if let end = session.flatMap({ TrackLayout.parseDate($0.end) }), now > end {
            return "Session ended · positions not live"
        }
        return "Positions not live"
    }
}

extension TimingSnapshot {
    /// Seconds since the freshest known position, if any driver has one.
    public func newestPositionAge(at now: Date) -> TimeInterval? {
        drivers.compactMap { $0.location?.timestamp }.max().map { now.timeIntervalSince($0) }
    }
}

extension TrackLayout {
    /// Width over height of the circuit's bounding box, so the map can take the circuit's own shape.
    public var aspectRatio: Double? {
        guard orientedPoints.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              let minX = orientedPoints.map(\.x).min(), let maxX = orientedPoints.map(\.x).max(),
              let minY = orientedPoints.map(\.y).min(), let maxY = orientedPoints.map(\.y).max(),
              maxX > minX, maxY > minY else { return nil }
        return (maxX - minX) / (maxY - minY)
    }
}

/// Keeps overlapping driver markers legible. Markers keep their place unless one would sit
/// closer than `minDistance` to a marker already placed; then it moves to the nearest free
/// spot on an expanding ring. Deterministic: the same input order always gives the same output.
public enum MarkerSpread {
    public static func separated(_ points: [TrackPoint], minDistance: Double, bounds: MarkerLabelPlacement.Rect? = nil) -> [TrackPoint] {
        var placed: [TrackPoint] = []
        for point in points {
            if isFree(point, among: placed, minDistance: minDistance) {
                placed.append(point)
                continue
            }
            placed.append(freeSpot(near: point, among: placed, minDistance: minDistance, bounds: bounds) ?? point)
        }
        return placed
    }

    private static func isFree(_ point: TrackPoint, among placed: [TrackPoint], minDistance: Double) -> Bool {
        !placed.contains { hypot($0.x - point.x, $0.y - point.y) < minDistance - 1e-9 }
    }

    private static func freeSpot(near origin: TrackPoint, among placed: [TrackPoint], minDistance: Double,
                                 bounds: MarkerLabelPlacement.Rect?) -> TrackPoint? {
        for ring in 1...16 {
            let radius = Double(ring) * minDistance
            let steps = 6 * ring
            for step in 0..<steps {
                let angle = 2 * Double.pi * Double(step) / Double(steps)
                let candidate = TrackPoint(x: origin.x + radius * cos(angle), y: origin.y + radius * sin(angle))
                if let bounds, candidate.x < bounds.x || candidate.x > bounds.maxX
                    || candidate.y < bounds.y || candidate.y > bounds.maxY { continue }
                if isFree(candidate, among: placed, minDistance: minDistance) { return candidate }
            }
        }
        return nil
    }
}
