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

// MARK: Selected-driver location wording

@Test func locationStateLabelsSayWhatIsKnown() throws {
    let located = try driver(position: 1, gap: nil, location: nowText)
    #expect(located.locationState(at: clock).label(for: located, at: clock) == "Located")
    let old = try driver(position: 1, gap: nil, location: "2026-11-06T11:59:00Z")   // 68 s before `clock`
    #expect(old.locationState(at: clock).label(for: old, at: clock) == "Stale · 68 s old")
    let none = try driver(position: 1, gap: nil)
    #expect(none.locationState(at: clock).label(for: none, at: clock) == "No position data")
}

// MARK: Calendar emphasis, countdown and caption

private func weekend(round: Int, raceStart: String?, raceDate: String = "2027-03-14") throws -> RaceWeekend {
    var race: [String: Any] = ["name": "Race", "date": raceDate]
    if let raceStart { race["start"] = raceStart }
    let object: [String: Any] = ["round": round, "name": "Sample GP", "circuit": "Sample", "country": "Demo", "sessions": [race]]
    return try JSONDecoder().decode(RaceWeekend.self, from: JSONSerialization.data(withJSONObject: object))
}

private let calendarNow = TrackLayout.parseDate("2027-03-10T10:00:00Z")!

@Test func onlyTheNextRaceIsExpandedAndPastRacesAreQuiet() throws {
    let past = try weekend(round: 1, raceStart: "2027-02-01T14:00:00Z")
    let next = try weekend(round: 2, raceStart: "2027-03-14T14:00:00Z")
    let later = try weekend(round: 3, raceStart: "2027-04-14T14:00:00Z")
    #expect(WeekendEmphasis(race: past, nextRound: 2, now: calendarNow) == .past)
    #expect(WeekendEmphasis(race: next, nextRound: 2, now: calendarNow) == .next)
    #expect(WeekendEmphasis(race: later, nextRound: 2, now: calendarNow) == .upcoming)
    #expect(WeekendEmphasis.next.startsExpanded)
    #expect(!WeekendEmphasis.upcoming.startsExpanded)
    #expect(!WeekendEmphasis.past.startsExpanded)
    #expect([WeekendEmphasis.next, .upcoming, .past].map(\.badge) == ["NEXT RACE", "UPCOMING", "PAST"])
}

@Test func aRaceThatHasStartedIsPastEvenIfItWasTheNextRoundNumber() throws {
    let started = try weekend(round: 2, raceStart: "2027-03-09T14:00:00Z")
    #expect(WeekendEmphasis(race: started, nextRound: 2, now: calendarNow) == .past)
}

@Test func raceCountdownCountsDownToTheRaceNotToPractice() throws {
    // 2027-03-10 10:00Z → 2027-03-14 14:00Z is exactly 4 days and 4 hours.
    let next = try weekend(round: 2, raceStart: "2027-03-14T14:00:00Z")
    #expect(next.countdownText(now: calendarNow) == "in 4d 4h")
    #expect(try weekend(round: 2, raceStart: nil).countdownText(now: calendarNow) == "Time TBC")
}

private func schedule(mode: String, source: String) throws -> RaceSchedule {
    let object: [String: Any] = ["season": 2027, "mode": mode, "source": source, "fetchedAt": "2027-03-10T10:00:00Z", "stale": false, "races": []]
    return try JSONDecoder().decode(RaceSchedule.self, from: JSONSerialization.data(withJSONObject: object))
}

@Test func timesCaptionNamesZoneAndSourceAndFlagsDemo() throws {
    #expect(try schedule(mode: "live", source: "Jolpica F1").timesCaption(timeZoneIdentifier: "Europe/Prague") == "Times in Europe/Prague · Jolpica F1")
    #expect(try schedule(mode: "demo", source: "Fictional sample calendar").timesCaption(timeZoneIdentifier: "UTC") == "Times in UTC · DEMO · Fictional sample calendar")
}

// MARK: Selected-driver label never covers its marker

private let mapBounds = MarkerLabelPlacement.Rect(x: 0, y: 0, width: 400, height: 300)

private func overlapsCircle(_ rect: MarkerLabelPlacement.Rect, cx: Double, cy: Double, r: Double) -> Bool {
    let nearestX = min(max(cx, rect.x), rect.maxX), nearestY = min(max(cy, rect.y), rect.maxY)
    return (cx - nearestX) * (cx - nearestX) + (cy - nearestY) * (cy - nearestY) < r * r
}

@Test func selectedLabelNeverOverlapsItsMarkerAnywhereOnTheMap() {
    for markerX in stride(from: 0.0, through: 400, by: 20) {
        for markerY in stride(from: 0.0, through: 300, by: 20) {
            let label = MarkerLabelPlacement.frame(markerX: markerX, markerY: markerY, markerRadius: 14,
                                                   labelWidth: 48, labelHeight: 20, bounds: mapBounds)
            #expect(!overlapsCircle(label, cx: markerX, cy: markerY, r: 14), "marker at \(markerX),\(markerY)")
            #expect(label.x >= mapBounds.x && label.maxX <= mapBounds.maxX, "label leaves the map sideways")
        }
    }
}

@Test func selectedLabelSitsAboveTheMarkerUnlessThatLeavesTheMap() {
    let middle = MarkerLabelPlacement.frame(markerX: 200, markerY: 150, markerRadius: 14, labelWidth: 48, labelHeight: 20, bounds: mapBounds)
    #expect(middle.maxY <= 150 - 14)               // entirely above the marker
    #expect(middle.x == 200 - 24)                  // centred on it
    let top = MarkerLabelPlacement.frame(markerX: 200, markerY: 10, markerRadius: 14, labelWidth: 48, labelHeight: 20, bounds: mapBounds)
    #expect(top.y >= 10 + 14)                      // no room above → below, still clear of the marker
    #expect(top.y >= mapBounds.y)
}
