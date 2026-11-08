import Foundation

public enum RaceControlSeverity: Int, Comparable, Sendable {
    case info, caution, critical
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What a race-control message means, derived from OpenF1's `flag` field and, for
/// safety-car messages that carry no flag, from the message text.
public enum RaceControlKind: Sendable, Equatable {
    case green, clear, yellow, doubleYellow, red, blue, blackAndWhite, black
    case chequered, safetyCar, virtualSafetyCar, info

    public init(flag: String?, message: String) {
        let text = message.uppercased()
        let explicit = flag?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // A critical flag is never downgraded to a caution because its message mentions the safety car.
        if explicit == "RED" {
            self = .red
        } else if explicit == "BLACK" {
            self = .black
        } else if text.contains("VIRTUAL SAFETY CAR") || text.contains("VSC") {
            self = .virtualSafetyCar
        } else if text.contains("SAFETY CAR") {
            self = .safetyCar
        } else {
            switch explicit {
            case "GREEN": self = .green
            case "CLEAR": self = .clear
            case "YELLOW": self = .yellow
            case "DOUBLE YELLOW": self = .doubleYellow
            case "RED": self = .red
            case "BLUE": self = .blue
            case "BLACK AND WHITE": self = .blackAndWhite
            case "BLACK": self = .black
            case "CHEQUERED": self = .chequered
            default:
                if text.contains("RED FLAG") { self = .red }
                else if text.contains("CHEQUERED") { self = .chequered }
                else { self = .info }
            }
        }
    }

    public var label: String {
        switch self {
        case .green: "Green flag"
        case .clear: "Track clear"
        case .yellow: "Yellow flag"
        case .doubleYellow: "Double yellow"
        case .red: "Red flag"
        case .blue: "Blue flag"
        case .blackAndWhite: "Black & white flag"
        case .black: "Black flag"
        case .chequered: "Chequered flag"
        case .safetyCar: "Safety car"
        case .virtualSafetyCar: "Virtual safety car"
        case .info: "Info"
        }
    }

    public var severity: RaceControlSeverity {
        switch self {
        case .red, .black: .critical
        case .yellow, .doubleYellow, .safetyCar, .virtualSafetyCar, .blackAndWhite: .caution
        case .green, .clear, .blue, .chequered, .info: .info
        }
    }
}

extension RaceMessage {
    public var kind: RaceControlKind { RaceControlKind(flag: flag, message: message) }
    public var timestamp: Date? { TrackLayout.parseDate(date) }

    /// What VoiceOver reads for the row: the flag, the time when the message has one, then the text.
    public func accessibilitySummary(timeText: String?) -> String {
        guard let timeText, !timeText.isEmpty else { return "\(kind.label). \(message)" }
        return "\(kind.label), \(timeText). \(message)"
    }
}

/// One answer to "can I trust what's on screen?": demo, live, stale or offline.
/// Colour is only one of its channels; every state also has its own label and symbol.
public struct FeedStatus: Equatable, Sendable {
    public enum Kind: Sendable, Equatable { case live, stale, offline, connecting }

    public let kind: Kind
    public let isDemo: Bool
    /// When the snapshot was last produced, if known.
    public let updatedAt: Date?
    /// Seconds since `updatedAt`, if known.
    public let age: TimeInterval?

    public static let staleAfter: TimeInterval = 30

    /// What the backend reports while it is still starting up. These are not failures, so they show
    /// CONNECTING; any other non-"connected" value (reconnecting, snapshot unavailable, ...) is stale.
    public static let startingUpstreamStates: Set<String> = ["connecting", "subscribing"]

    public static func resolve(snapshot: TimingSnapshot?, connected: Bool, hasError: Bool, now: Date) -> Self {
        guard let snapshot else {
            return Self(kind: hasError ? .offline : .connecting, isDemo: false, updatedAt: nil, age: nil)
        }
        let isDemo = snapshot.mode == "demo"
        let updated = snapshot.updatedAt.flatMap(TrackLayout.parseDate)
        let age = updated.map { now.timeIntervalSince($0) }
        if !connected { return Self(kind: .offline, isDemo: isDemo, updatedAt: updated, age: age) }
        // Demo timing is simulated; it never goes stale and says so instead.
        if isDemo { return Self(kind: .live, isDemo: true, updatedAt: updated, age: age) }
        if startingUpstreamStates.contains(snapshot.upstream) {
            return Self(kind: .connecting, isDemo: false, updatedAt: updated, age: age)
        }
        if snapshot.upstream != "connected" { return Self(kind: .stale, isDemo: false, updatedAt: updated, age: age) }
        guard let age else { return Self(kind: .stale, isDemo: false, updatedAt: nil, age: nil) }
        return Self(kind: age > staleAfter ? .stale : .live, isDemo: false, updatedAt: updated, age: age)
    }

    /// How old the timing is in words ("45 s", "38 min", "1 h 12 min"); nil when the age is unknown.
    public var ageText: String? { age.map { DurationText.compact(seconds: $0) } }

    /// Short uppercase label. Demo data is never labelled plain LIVE.
    public var label: String {
        let base: String
        switch kind {
        case .live: base = "LIVE"
        case .stale: base = "STALE"
        case .offline: base = "OFFLINE"
        case .connecting: base = "CONNECTING"
        }
        guard isDemo else { return base }
        return kind == .live ? "DEMO" : "DEMO · \(base)"
    }

    /// Full sentence for VoiceOver; says demo data is simulated, never "live".
    public var spokenDescription: String {
        let ageText = self.ageText
        switch (isDemo, kind) {
        case (true, .live): return "Demo data. Timing is simulated, not live."
        case (true, _): return "Demo data, and the connection to the timing server is down."
        case (false, .live): return ageText.map { "Live. Last timing \($0) ago." } ?? "Live."
        case (false, .stale): return ageText.map { "Stale. No new timing for \($0)." } ?? "Stale. Timing may be out of date."
        case (false, .offline): return "Offline. Not connected to the timing server."
        case (false, .connecting): return "Connecting to the timing server."
        }
    }
}

extension TimingDriver {
    /// The gap as a spoken phrase: "2.431 seconds behind the leader", "1 lap behind the leader".
    public var spokenGap: String { Self.spokenGap(gap, leader: position == 1, behind: "the leader") }

    /// The gap to the car ahead: "1.187 seconds behind the car ahead".
    public var spokenInterval: String { Self.spokenGap(interval, leader: position == 1, behind: "the car ahead") }

    private static func spokenGap(_ value: String?, leader: Bool, behind reference: String) -> String {
        guard let gap = value?.trimmingCharacters(in: .whitespaces), !gap.isEmpty else {
            return leader ? "leader" : "gap unavailable"
        }
        let upper = gap.uppercased()
        if upper.hasPrefix("+"), upper.hasSuffix("LAP") || upper.hasSuffix("LAPS") {
            let count = upper.dropFirst().split(separator: " ").first.map(String.init) ?? "1"
            return "\(count) \(count == "1" ? "lap" : "laps") behind \(reference)"
        }
        if upper.hasPrefix("+"), Double(upper.dropFirst()) != nil {
            return "\(gap.dropFirst()) seconds behind \(reference)"
        }
        return "gap \(gap)"
    }

    /// The timing column's figure as a spoken phrase.
    public func spokenTiming(_ metric: TimingMetric) -> String {
        switch metric {
        case .interval: spokenInterval
        case .gapToLeader: spokenGap
        case .fastestLap: formattedBestLap == "—" ? "fastest lap unavailable" : "fastest lap \(formattedBestLap)"
        }
    }

    /// One sentence for VoiceOver: position, driver, team, gap, last lap, tyre.
    public var accessibilitySummary: String { accessibilitySummary(showingGap: true) }

    /// Same sentence; without a gap column the gap is left out instead of saying "gap unavailable" on every row.
    public func accessibilitySummary(showingGap: Bool) -> String {
        accessibilitySummary(showingGap: showingGap, metric: .gapToLeader)
    }

    /// Same sentence with the timing column's current figure in place of the gap to the leader.
    public func accessibilitySummary(showingGap: Bool, metric: TimingMetric) -> String {
        let place = position.map { "Position \($0)" } ?? "Position unavailable"
        let lap = formattedLap == "—" ? "last lap unavailable" : "last lap \(formattedLap)"
        let parts = [place, name, team] + (showingGap ? [spokenTiming(metric)] : []) + [lap, TyreCompound(compound).label]
        return parts.joined(separator: ", ")
    }
}
