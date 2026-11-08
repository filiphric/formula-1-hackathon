import Foundation
import Testing
@testable import FormulaCore

private func results() throws -> RaceResults {
    let url = Bundle.module.url(forResource: "results", withExtension: "json", subdirectory: "Fixtures")!
    return try JSONDecoder().decode(RaceResults.self, from: Data(contentsOf: url))
}

@Test func resultsContractDecodesWinnerGapLappedAndRetired() throws {
    let race = try results()
    #expect(race.season == 2025 && race.round == 1)
    #expect(race.entries.map(\.position) == [1, 2, 3, 15, 18])
    #expect(race.entries[0].outcome == "1:42:06.304")
    #expect(race.entries[1].outcome == "+0.895")
    #expect(race.entries[3].outcome == "+1 Lap")
    #expect(race.entries[4].outcome == "Retired")
    #expect(race.entries[0].fastestLap && !race.entries[2].fastestLap)
}

@Test func pointsAreWholeOrHalfAndAbsentWhenNothingScored() throws {
    let entries = try results().entries
    #expect(entries[0].pointsText == "25")
    #expect(entries[3].pointsText == "0.5")
    #expect(entries[4].pointsText == nil)
}

@Test func unclassifiedDriversAreMarkedAndMissingCodesFallBackToTheSurname() throws {
    let entries = try results().entries
    #expect(entries[0].isClassified && !entries[4].isClassified)
    #expect(entries[4].positionText == "R")
    #expect(entries[4].displayCode == "DOO")
    #expect(entries[0].displayCode == "NOR")
}

@Test func spokenSummaryNamesPositionTeamOutcomePointsFastestLapAndPitStops() throws {
    let entries = try results().entries
    #expect(entries[0].spokenSummary == "Position 1, Lando Norris, McLaren, 1:42:06.304, 25 points, Fastest lap, 2 pit stops")
    #expect(entries[4].spokenSummary == "Not classified, Jack Doohan, Alpine F1 Team, Retired, No pit stops")
}

@Test func pitStopsAreReadAndWordedForEveryCountIncludingUnknown() throws {
    let entries = try results().entries
    #expect(entries.map(\.pitStops) == [2, 1, 3, nil, 0])
    #expect(entries.map(\.pitStopsText) == ["2 stops", "1 stop", "3 stops", nil, "No stops"])
    #expect(entries[0].detailLine == "McLaren · 2 stops")
    #expect(entries[3].detailLine == "Williams", "unknown stops are left out, not shown as none")
}

@Test func spokenSummaryIncludesPitStopsOnlyWhenKnown() throws {
    let entries = try results().entries
    #expect(entries[0].spokenSummary.hasSuffix("Fastest lap, 2 pit stops"))
    #expect(entries[1].spokenSummary.hasSuffix("18 points, 1 pit stop"))
    #expect(entries[4].spokenSummary == "Not classified, Jack Doohan, Alpine F1 Team, Retired, No pit stops")
    #expect(!entries[3].spokenSummary.contains("stop"))
}

@Test func resultsEndpointKeepsHostAndTLSWithoutTimingQuery() {
    #expect(RaceResults.endpoint(from: "wss://example.com:9443/live?token=private#x", season: 2025, round: 7)?.absoluteString == "https://example.com:9443/results/2025/7")
    #expect(RaceResults.endpoint(from: "ws://localhost:8787/live", season: 2026, round: 12)?.absoluteString == "http://localhost:8787/results/2026/12")
    #expect(RaceResults.endpoint(from: "https://example.com", season: 2025, round: 1) == nil)
    #expect(RaceResults.endpoint(from: "ws://user:password@example.com/live", season: 2025, round: 1) == nil)
}
