import Foundation
import Testing
@testable import FormulaCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

// MARK: Countdown ("in 3d 4h")

@Test func countdownShowsDaysAndHoursForFarAwayRaces() {
    // 3 days + 4 hours + 59 minutes: units are truncated, so minutes never appear next to days.
    let target = now.addingTimeInterval(3 * 86_400 + 4 * 3_600 + 59 * 60)
    #expect(Countdown.text(until: target, now: now) == "in 3d 4h")
    #expect(Countdown.text(until: now.addingTimeInterval(2 * 86_400), now: now) == "in 2d")
}

@Test func countdownShowsHoursAndMinutesWithinADay() {
    #expect(Countdown.text(until: now.addingTimeInterval(5 * 3_600 + 12 * 60 + 30), now: now) == "in 5h 12m")
    #expect(Countdown.text(until: now.addingTimeInterval(86_400 - 60), now: now) == "in 23h 59m")
    #expect(Countdown.text(until: now.addingTimeInterval(2 * 3_600), now: now) == "in 2h")
}

@Test func countdownShowsMinutesWithinAnHourAndNeverClaimsZero() {
    #expect(Countdown.text(until: now.addingTimeInterval(45 * 60), now: now) == "in 45m")
    #expect(Countdown.text(until: now.addingTimeInterval(3_599), now: now) == "in 59m")
    #expect(Countdown.text(until: now.addingTimeInterval(59), now: now) == "in under a minute")
}

@Test func countdownSaysStartedOnceTheStartHasPassed() {
    #expect(Countdown.text(until: now, now: now) == "Started")
    #expect(Countdown.text(until: now.addingTimeInterval(-3_600), now: now) == "Started")
}

// MARK: Timing tower columns

@Test func everyLayoutKeepsPositionDriverGapAndTyre() {
    for layout in TimingLayout.allCases {
        for column in [TimingColumn.position, .driver, .gap, .tyre] { #expect(layout.shows(column)) }
    }
}

@Test func narrowerLayoutsDropTeamFirstThenLastLapAndNothingElse() {
    // Requirement: at compact width drop LAST LAP or team before any horizontal scrolling.
    #expect(TimingLayout.wide.columns == [.position, .driver, .team, .gap, .lastLap, .tyre])
    #expect(TimingLayout.standard.columns == [.position, .driver, .gap, .lastLap, .tyre])
    #expect(TimingLayout.compact.columns == [.position, .driver, .gap, .tyre])
    #expect(TimingLayout.allCases == [.wide, .standard, .compact])
}

@Test func gapAndLastLapAreSeparateColumns() {
    // The old combined "GAP / LAP" cell must not come back.
    #expect(TimingLayout.wide.shows(.gap) && TimingLayout.wide.shows(.lastLap))
    #expect(!TimingLayout.compact.shows(.lastLap))
    #expect(!TimingLayout.standard.shows(.team))
}

// MARK: Gap text and leader

private func driver(position: Int?, gap: String?, location: String? = nil) throws -> TimingDriver {
    var object: [String: Any] = ["number": 4, "name": "Lando Norris", "acronym": "NOR", "team": "McLaren", "color": "FF8000"]
    if let position { object["position"] = position }
    if let gap { object["gap"] = gap }
    if let location { object["location"] = ["x": 1, "y": 2, "date": location] }
    return try JSONDecoder().decode(TimingDriver.self, from: JSONSerialization.data(withJSONObject: object))
}

@Test func leaderShowsLeaderInTheGapColumnEvenWithoutAGap() throws {
    let leader = try driver(position: 1, gap: nil)
    #expect(leader.isLeader)
    #expect(leader.gapText == "LEADER")
    #expect(try driver(position: 1, gap: "+0.0").gapText == "LEADER")
}

@Test func otherDriversShowTheirGapOrADashWhenUnknown() throws {
    let second = try driver(position: 2, gap: "+1.234")
    #expect(!second.isLeader)
    #expect(second.gapText == "+1.234")
    #expect(try driver(position: 2, gap: nil).gapText == "—")
    #expect(try driver(position: 2, gap: "  ").gapText == "—")
    #expect(try driver(position: nil, gap: nil).gapText == "—")
}

// MARK: "N of M drivers located"

private func snapshot(_ drivers: [TimingDriver]) -> TimingSnapshot {
    TimingSnapshot(mode: "live", upstream: "connected", updatedAt: nil, session: nil, drivers: drivers, messages: [], track: nil)
}

private let nowText = "2026-11-06T12:00:05Z"
private let clock = TrackLayout.parseDate("2026-11-06T12:00:08Z")!

@Test func locationSummaryCountsLocatedOverTotal() throws {
    let drivers = [try driver(position: 1, gap: nil, location: nowText), try driver(position: 2, gap: "+1", location: nowText),
                   try driver(position: 3, gap: "+2"), try driver(position: 4, gap: "+3")]
    #expect(snapshot(drivers).locationSummary(at: clock) == "2 of 4 drivers located")
}

@Test func locationSummaryAddsStaleCountOnlyWhenSomeAreStale() throws {
    let old = "2026-11-06T11:00:00Z"
    let drivers = [try driver(position: 1, gap: nil, location: nowText), try driver(position: 2, gap: "+1", location: old),
                   try driver(position: 3, gap: "+2", location: old)]
    // Stale drivers still have a known (old) position, so they count as located.
    #expect(snapshot(drivers).locationSummary(at: clock) == "3 of 3 drivers located · 2 stale")
}

@Test func locationSummaryHandlesNoDriversAndSingularDriver() throws {
    #expect(snapshot([]).locationSummary(at: clock) == "0 of 0 drivers located")
    #expect(snapshot([try driver(position: 1, gap: nil)]).locationSummary(at: clock) == "0 of 1 driver located")
}

@Test func driverLocationStateIsLocatedStaleOrUnavailable() throws {
    #expect(try driver(position: 1, gap: nil, location: nowText).locationState(at: clock) == .located)
    #expect(try driver(position: 1, gap: nil, location: "2026-11-06T11:00:00Z").locationState(at: clock) == .stale)
    #expect(try driver(position: 1, gap: nil).locationState(at: clock) == .unavailable)
}
