import Foundation

public struct RaceSchedule: Codable, Sendable {
    public let season: Int
    public let mode: String
    public let source: String
    public let fetchedAt: String
    public let stale: Bool
    public let races: [RaceWeekend]
    public var expiresIn: TimeInterval? = nil

    public static func currentSeason(at now: Date = .now) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.component(.year, from: now)
    }

    public static func availableSeasons(at now: Date = .now) -> [Int] {
        Array((2023...max(2023, currentSeason(at: now) + 1)).reversed())
    }

    public var fetchedDate: Date? { parseScheduleDate(fetchedAt) }

    public func isStale(elapsedSinceValidation elapsed: TimeInterval) -> Bool {
        // Backend freshness is authoritative at receipt; device/server wall clocks
        // need not agree. The client expires its view using elapsed time only.
        stale || elapsed < 0 || elapsed >= min(max(expiresIn ?? 0, 0), 900)
    }

    public func nextRace(at now: Date) -> RaceWeekend? {
        races.filter { !$0.isPast(at: now) }.min {
            ($0.raceDate ?? .distantFuture) < ($1.raceDate ?? .distantFuture)
        }
    }

    public static func endpoint(from timingEndpoint: String, season: Int) -> URL? {
        guard var components = URLComponents(string: timingEndpoint),
              let scheme = components.scheme?.lowercased(), ["ws", "wss"].contains(scheme),
              components.host != nil, components.user == nil, components.password == nil else { return nil }
        components.scheme = scheme == "wss" ? "https" : "http"
        let prefix = components.percentEncodedPath.split(separator: "/").dropLast().joined(separator: "/")
        components.percentEncodedPath = (prefix.isEmpty ? "" : "/" + prefix) + "/schedule/\(season)"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

public struct RaceWeekend: Codable, Identifiable, Sendable {
    public var id: Int { round }
    public let round: Int
    public let name: String
    public let circuit: String
    public let country: String
    public let sessions: [ScheduledSession]

    public var raceDate: Date? {
        guard let race = sessions.first(where: { $0.name == "Race" }) else { return nil }
        return race.startDate ?? race.calendarDate(timeZone: .autoupdatingCurrent)
    }

    public func isPast(at now: Date, timeZone: TimeZone = .autoupdatingCurrent) -> Bool {
        guard let race = sessions.first(where: { $0.name == "Race" }) else { return false }
        if let start = race.startDate { return start <= now }
        // A date without a time is past only after that whole local calendar day.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let day = race.calendarDate(timeZone: timeZone),
              let end = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
        return end <= now
    }
}

public struct ScheduledSession: Codable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let date: String
    public let start: String?

    public var startDate: Date? {
        start.flatMap(parseScheduleDate)
    }

    public func calendarDate(timeZone: TimeZone) -> Date? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.timeZone = timeZone
        parser.dateFormat = "yyyy-MM-dd"
        return parser.date(from: date)
    }

    public func localDate(timeZone: TimeZone = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) -> String {
        guard let day = startDate ?? calendarDate(timeZone: timeZone) else { return date }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter.string(from: day)
    }

    public func localTime(timeZone: TimeZone = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) -> String {
        guard let startDate else { return "Time TBC" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.timeStyle = .short
        return formatter.string(from: startDate)
    }
}

private func parseScheduleDate(_ value: String) -> Date? {
    let parser = ISO8601DateFormatter()
    if let date = parser.date(from: value) { return date }
    parser.formatOptions.insert(.withFractionalSeconds)
    return parser.date(from: value)
}
