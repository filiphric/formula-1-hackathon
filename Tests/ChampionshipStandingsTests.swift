import Foundation
import Testing
@testable import FormulaCore

private func standings() throws -> ChampionshipStandings {
    let url = Bundle.module.url(forResource: "standings", withExtension: "json", subdirectory: "Fixtures")!
    return try JSONDecoder().decode(ChampionshipStandings.self, from: Data(contentsOf: url))
}

private func driver(_ code: String, position: Int?, number: Int = 99, color: String = "FF8000") -> TimingDriver {
    TimingDriver(number: number, name: "\(code) Driver", acronym: code, team: "Team", color: color, position: position,
                 gap: nil, lap: nil, lapTime: nil, compound: nil, location: nil)
}

private func snapshot(session: String = "Race", mode: String = "live", start: String = "2025-12-07T13:00:00Z",
                      end: String = "2025-12-07T15:00:00Z", _ drivers: [TimingDriver]) -> TimingSnapshot {
    TimingSnapshot(mode: mode, upstream: "connected", updatedAt: nil,
                   session: RaceSession(name: session, circuit: "Yas Marina", start: start, end: end),
                   drivers: drivers, messages: [], track: nil)
}

private let raceTime = TrackLayout.parseDate("2025-12-07T14:00:00Z")!

@Test func standingsContractDecodesPointsWinsAndMissingCodes() throws {
    let table = try standings()
    #expect(table.season == 2025 && table.round == 24)
    #expect(table.entries.map(\.position) == [1, 2, 3, 4])
    #expect(table.entries[0].points == 423 && table.entries[3].points == 0.5)
    #expect(table.entries[1].wins == 8)
    #expect(table.entries[3].code == nil)
}

@Test func standingsEndpointKeepsHostAndTLSWithoutTimingQuery() {
    #expect(ChampionshipStandings.endpoint(from: "wss://example.com:9443/live?token=private#x", season: 2025)?.absoluteString == "https://example.com:9443/standings/2025")
    #expect(ChampionshipStandings.endpoint(from: "ws://localhost:8787/live", season: 2026)?.absoluteString == "http://localhost:8787/standings/2026")
    #expect(ChampionshipStandings.endpoint(from: "https://example.com", season: 2025) == nil)
}

@Test func raceAndSprintPointsFollowTheFormulaOnePointsSystem() {
    #expect((1...11).map(ChampionshipSession.race.points) == [25, 18, 15, 12, 10, 8, 6, 4, 2, 1, 0])
    #expect((1...9).map(ChampionshipSession.sprint.points) == [8, 7, 6, 5, 4, 3, 2, 1, 0])
    #expect(ChampionshipSession.race.points(forPosition: 0) == 0)
}

@Test func onlyRaceAndSprintSessionsScore() {
    #expect(ChampionshipSession(sessionName: "Race") == .race)
    #expect(ChampionshipSession(sessionName: "Race · Sample data") == .race)
    #expect(ChampionshipSession(sessionName: "Sprint") == .sprint)
    #expect(ChampionshipSession(sessionName: "Sprint Qualifying") == nil)
    #expect(ChampionshipSession(sessionName: "Sprint Shootout") == nil)
    #expect(ChampionshipSession(sessionName: "Qualifying") == nil)
    #expect(ChampionshipSession(sessionName: "Practice 1") == nil)
}

@Test func runningOrderAddsRacePointsAndReordersTheChampionship() throws {
    // Before the race: Norris 423, Verstappen 421, Piastri 410. Verstappen leads the race, Norris is second,
    // Piastri is eleventh. So Verstappen 421 + 25 = 446, Norris 423 + 18 = 441, Piastri 410 + 0 = 410.
    let live = snapshot([driver("VER", position: 1), driver("NOR", position: 2), driver("PIA", position: 11)])
    let rows = ChampionshipProjection.rows(standings: try standings(), snapshot: live, session: .race)
    #expect(rows.map(\.code) == ["VER", "NOR", "PIA", nil])
    #expect(rows.map(\.projectedPoints) == [446, 441, 410, 0.5])
    #expect(rows[0].gained == 25 && rows[0].position == 2 && rows[0].projectedPosition == 1 && rows[0].change == 1)
    #expect(rows[1].change == -1)
    #expect(rows[2].change == 0)
}

@Test func lowerRunningOrderScoresLowerPointsAndALapOneCrashScoresNothing() throws {
    // Piastri is tenth (1 point): 411. Norris has no position yet: no points, stays on 423.
    let live = snapshot([driver("PIA", position: 10), driver("NOR", position: nil)])
    let rows = ChampionshipProjection.rows(standings: try standings(), snapshot: live, session: .race)
    let byCode = Dictionary(uniqueKeysWithValues: rows.compactMap { row in row.code.map { ($0, row) } })
    #expect(byCode["PIA"]?.projectedPoints == 411)
    #expect(byCode["NOR"]?.projectedPoints == 423)
}

@Test func sprintUsesTheSprintScale() throws {
    let live = snapshot(session: "Sprint", [driver("PIA", position: 1)])
    let rows = ChampionshipProjection.rows(standings: try standings(), snapshot: live, session: .sprint)
    #expect(rows.first { $0.code == "PIA" }?.gained == 8)
}

@Test func withoutAScoringSessionTheOfficialTableIsUnchanged() throws {
    let live = snapshot(session: "Qualifying", [driver("PIA", position: 1)])
    let rows = ChampionshipProjection.rows(standings: try standings(), snapshot: live, session: nil)
    #expect(rows.map(\.code) == ["NOR", "VER", "PIA", nil])
    #expect(rows.allSatisfy { $0.gained == 0 && $0.change == 0 })
    #expect(rows.map(\.projectedPoints) == [423, 421, 410, 0.5])
}

@Test func tiedPointsKeepTheOfficialOrderAndADebutantStartsOnZero() throws {
    // Norris 423 + 0 ties Verstappen 421 + 2 (ninth is 2 points): 423 each, and the official leader stays ahead.
    // A driver the table does not list (RAN) is added with no points and scores from the running order.
    let live = snapshot([driver("VER", position: 9), driver("RAN", position: 1, number: 7)])
    let rows = ChampionshipProjection.rows(standings: try standings(), snapshot: live, session: .race)
    // Order: Norris 423, Verstappen 423 (tie, official order), Piastri 410, the debutant 25, then Doohan 0.5.
    #expect(rows.map(\.code) == ["NOR", "VER", "PIA", "RAN", nil])
    #expect(rows.map(\.projectedPoints) == [423, 423, 410, 25, 0.5])
    #expect(rows[1].change == 0)
}

@Test func projectionOnlyRunsWhileARealSessionIsInProgressButAlwaysInDemo() {
    let race = snapshot([])
    #expect(ChampionshipProjection.scoringSession(for: race, now: raceTime) == .race)
    #expect(ChampionshipProjection.scoringSession(for: race, now: raceTime.addingTimeInterval(-7200)) == nil)
    #expect(ChampionshipProjection.scoringSession(for: race, now: raceTime.addingTimeInterval(7200)) == nil)
    let qualifying = snapshot(session: "Qualifying", [])
    #expect(ChampionshipProjection.scoringSession(for: qualifying, now: raceTime) == nil)
    let demo = snapshot(session: "Race · Sample data", mode: "demo", start: "2020-01-01T00:00:00Z", end: "2020-01-01T00:00:00Z", [])
    #expect(ChampionshipProjection.scoringSession(for: demo, now: raceTime) == .race)
}

@Test func aRaceRunningPastItsScheduledEndKeepsProjectingWhileCarsStillReport() {
    // The request: a race that overruns (red flag) must not lose its projection while cars are still racing.
    func racing(locatedAt date: String) -> TimingSnapshot {
        var live = driver("NOR", position: 1)
        live = TimingDriver(number: live.number, name: live.name, acronym: live.acronym, team: live.team, color: live.color,
                            position: 1, gap: nil, lap: nil, lapTime: nil, compound: nil,
                            location: DriverLocation(x: 1, y: 2, date: date))
        return snapshot([live])
    }
    let afterEnd = TrackLayout.parseDate("2025-12-07T15:10:00Z")!
    #expect(ChampionshipProjection.scoringSession(for: racing(locatedAt: "2025-12-07T15:09:58Z"), now: afterEnd) == .race)
    // Cars that stopped reporting 20 minutes ago mean the race is over: the official table takes over.
    #expect(ChampionshipProjection.scoringSession(for: racing(locatedAt: "2025-12-07T14:50:00Z"), now: afterEnd) == nil)
}

@Test func teamColourComesFromTheLiveFeedAndSpeechStatesTheProjection() throws {
    let live = snapshot([driver("VER", position: 1, color: "3671C6"), driver("NOR", position: 2)])
    let rows = ChampionshipProjection.rows(standings: try standings(), snapshot: live, session: .race)
    #expect(rows[0].color == "3671C6")
    #expect(rows.last?.color == nil)
    #expect(rows[0].spokenSummary(projecting: true) == "Position 1, Max Verstappen, Red Bull, 446 points, plus 25 from the current running order, up 1 place")
    #expect(rows[0].spokenSummary(projecting: false) == "Position 2, Max Verstappen, Red Bull, 421 points")
}
