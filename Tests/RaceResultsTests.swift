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

@Test func spokenSummaryNamesPositionTeamOutcomePointsAndFastestLap() throws {
    let entries = try results().entries
    #expect(entries[0].spokenSummary == "Position 1, Lando Norris, McLaren, 1:42:06.304, 25 points, Fastest lap")
    #expect(entries[4].spokenSummary == "Not classified, Jack Doohan, Alpine F1 Team, Retired")
}

@Test func resultsEndpointKeepsHostAndTLSWithoutTimingQuery() {
    #expect(RaceResults.endpoint(from: "wss://example.com:9443/live?token=private#x", season: 2025, round: 7)?.absoluteString == "https://example.com:9443/results/2025/7")
    #expect(RaceResults.endpoint(from: "ws://localhost:8787/live", season: 2026, round: 12)?.absoluteString == "http://localhost:8787/results/2026/12")
    #expect(RaceResults.endpoint(from: "https://example.com", season: 2025, round: 1) == nil)
    #expect(RaceResults.endpoint(from: "ws://user:password@example.com/live", season: 2025, round: 1) == nil)
}
