import Foundation

/// The official driver standings, from `GET /standings/{season}`.
public struct ChampionshipStandings: Codable, Sendable, Equatable {
    public let season: Int
    /// The last round the points include; nil before the season's first race.
    public let round: Int?
    public let mode: String
    public let source: String
    public let fetchedAt: String
    public let stale: Bool
    /// Empty until the source publishes the first standings of the season.
    public let entries: [StandingEntry]

    public init(season: Int, round: Int?, mode: String, source: String, fetchedAt: String, stale: Bool, entries: [StandingEntry]) {
        self.season = season; self.round = round; self.mode = mode; self.source = source
        self.fetchedAt = fetchedAt; self.stale = stale; self.entries = entries
    }

    public static func endpoint(from timingEndpoint: String, season: Int) -> URL? {
        backendURL(from: timingEndpoint, route: "standings/\(season)")
    }
}

public struct StandingEntry: Codable, Identifiable, Sendable, Equatable {
    public var id: String { code ?? name }
    public let position: Int
    public let code: String?
    public let name: String
    public let team: String
    public let points: Double
    public let wins: Int

    public init(position: Int, code: String?, name: String, team: String, points: Double, wins: Int) {
        self.position = position; self.code = code; self.name = name
        self.team = team; self.points = points; self.wins = wins
    }
}

/// The points a classified finishing position is worth in a session.
public enum ChampionshipSession: Sendable, Equatable {
    case race, sprint

    /// Points for P1, P2 ... Everyone below the last listed position scores nothing.
    public var scale: [Int] {
        switch self {
        case .race: [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
        case .sprint: [8, 7, 6, 5, 4, 3, 2, 1]
        }
    }

    public func points(forPosition position: Int) -> Int {
        position >= 1 && position <= scale.count ? scale[position - 1] : 0
    }

    /// "Race", "Race · Sample data" and "Sprint" score; practice, qualifying and sprint qualifying do not.
    public init?(sessionName: String) {
        let name = sessionName.lowercased()
        if name.hasPrefix("sprint") {
            guard !name.contains("qualifying"), !name.contains("shootout") else { return nil }
            self = .sprint
        } else if name.hasPrefix("race") {
            self = .race
        } else {
            return nil
        }
    }
}

/// One line of the championship table, with what the running order would change.
public struct StandingRow: Identifiable, Sendable, Equatable {
    public var id: String { code ?? name }
    public let code: String?
    public let name: String
    public let team: String
    /// Team colour hex from the live timing feed, when this driver is on it.
    public let color: String?
    public let wins: Int
    /// The official points, which do not include the session being run.
    public let points: Double
    /// Points the current running order adds; zero when nothing is being projected.
    public let gained: Int
    public let position: Int
    /// Where the driver would stand with those points; equals `position` when nothing is projected.
    public let projectedPosition: Int

    public var projectedPoints: Double { points + Double(gained) }
    /// Positive when the running order lifts the driver in the championship.
    public var change: Int { position - projectedPosition }
}

public enum ChampionshipProjection {
    /// What the live session is worth to the championship, or nil when it is not scoring right now.
    /// Demo sessions always project, since their clock is meaningless; a real one only between its start and end,
    /// because the official standings include the race only after it is classified.
    public static func scoringSession(for snapshot: TimingSnapshot, now: Date) -> ChampionshipSession? {
        guard let session = snapshot.session, let kind = ChampionshipSession(sessionName: session.name) else { return nil }
        if snapshot.mode == "demo" { return kind }
        guard let start = TrackLayout.parseDate(session.start), let end = TrackLayout.parseDate(session.end),
              now >= start, now <= end else { return nil }
        return kind
    }

    /// The table in projected order. Drivers match the timing feed by three-letter code. A driver on the
    /// feed but missing from the official table (a debutant) starts on zero. Ties keep the official order,
    /// because the real tie-break counts finishes the feed does not carry.
    public static func rows(standings: ChampionshipStandings, snapshot: TimingSnapshot?, session: ChampionshipSession?) -> [StandingRow] {
        var live: [String: TimingDriver] = [:]
        for driver in snapshot?.drivers ?? [] { live[driver.acronym] = driver }

        func gained(_ code: String?) -> Int {
            guard let session, let code, let position = live[code]?.position else { return 0 }
            return session.points(forPosition: position)
        }

        struct Draft { let entry: StandingEntry; let gained: Int; let rank: Int }
        var drafts = standings.entries.enumerated().map { Draft(entry: $1, gained: gained($1.code), rank: $0) }
        if session != nil {
            let known = Set(standings.entries.compactMap(\.code))
            let debutants = live.values.filter { !known.contains($0.acronym) }.sorted { $0.number < $1.number }
            for driver in debutants {
                let entry = StandingEntry(position: drafts.count + 1,
                                          code: driver.acronym, name: driver.name, team: driver.team, points: 0, wins: 0)
                drafts.append(Draft(entry: entry, gained: gained(driver.acronym), rank: drafts.count))
            }
        }
        let ordered = drafts.sorted {
            let a = $0.entry.points + Double($0.gained), b = $1.entry.points + Double($1.gained)
            return a != b ? a > b : $0.rank < $1.rank
        }
        let projected = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.rank, $0 + 1) })
        return drafts.map { draft in
            StandingRow(code: draft.entry.code, name: draft.entry.name, team: draft.entry.team,
                        color: draft.entry.code.flatMap { live[$0]?.color }, wins: draft.entry.wins,
                        points: draft.entry.points, gained: draft.gained, position: draft.rank + 1,
                        projectedPosition: projected[draft.rank] ?? draft.rank + 1)
        }
        .sorted { $0.projectedPosition < $1.projectedPosition }
    }
}

extension StandingRow {
    /// Whole numbers without a trailing ".0"; half points keep theirs.
    public static func pointsText(_ points: Double) -> String {
        points == points.rounded() ? String(Int(points)) : String(points)
    }

    public func spokenSummary(projecting: Bool) -> String {
        let shown = projecting ? projectedPosition : position
        let total = projecting ? projectedPoints : points
        var parts = ["Position \(shown)", name, team, "\(Self.pointsText(total)) \(total == 1 ? "point" : "points")"]
        if projecting, gained > 0 { parts.append("plus \(gained) from the current running order") }
        if projecting, change != 0 {
            parts.append(change > 0 ? "up \(change) \(change == 1 ? "place" : "places")" : "down \(-change) \(change == -1 ? "place" : "places")")
        }
        return parts.joined(separator: ", ")
    }
}
