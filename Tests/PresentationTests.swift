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
    let old = try driver(position: 1, gap: nil, location: "2026-11-06T11:59:00Z")   // 68 s before `clock`, which is 1 min
    #expect(old.locationState(at: clock).label(for: old, at: clock) == "Stale · 1 min old")
    let none = try driver(position: 1, gap: nil)
    #expect(none.locationState(at: clock).label(for: none, at: clock) == "No position data")
}

// MARK: Calendar emphasis, countdown and caption

private func weekend(round: Int, raceStart: String?, raceDate: String = "2027-03-14") throws -> RaceWeekend {
    var race: [String: Any] = ["name": "Race", "date": raceDate]
    if let raceStart { race["start"] = raceStart }
    // Practice comes first and is earlier than the race, so counting to the wrong session shows up.
    let practice: [String: Any] = ["name": "Practice 1", "date": "2027-03-12", "start": "2027-03-12T10:00:00Z"]
    let object: [String: Any] = ["round": round, "name": "Sample GP", "circuit": "Sample", "country": "Demo", "sessions": [practice, race]]
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

// MARK: Switching the timing column (interval, gap to leader, fastest lap)

/// Third on the road: 7.5 s behind the leader, 1.25 s behind the car ahead, fastest lap 1:30.500
/// but 1:31.300 on the last one.
private func racer(position: Int = 3, gap: String? = "+7.500", interval: String? = "+1.250",
                   bestLap: Double? = 90.5) throws -> TimingDriver {
    var object: [String: Any] = ["number": 4, "name": "Lando Norris", "acronym": "NOR", "team": "McLaren",
                                 "color": "FF8000", "position": position, "lapTime": 91.3, "compound": "SOFT"]
    if let gap { object["gap"] = gap }
    if let interval { object["interval"] = interval }
    if let bestLap { object["bestLap"] = bestLap }
    return try JSONDecoder().decode(TimingDriver.self, from: JSONSerialization.data(withJSONObject: object))
}

@Test func tappingCyclesIntervalThenGapToLeaderThenFastestLapThenBackAround() {
    #expect(TimingMetric.allCases == [.interval, .gapToLeader, .fastestLap])
    #expect(TimingMetric.interval.next == .gapToLeader)
    #expect(TimingMetric.gapToLeader.next == .fastestLap)
    #expect(TimingMetric.fastestLap.next == .interval)
}

@Test func eachMetricShowsItsOwnFigureForTheSameDriver() throws {
    let driver = try racer()
    #expect(driver.timingText(.interval) == "+1.250")
    #expect(driver.timingText(.gapToLeader) == "+7.500")
    #expect(driver.timingText(.fastestLap) == "1:30.500")
    // The last-lap column is unaffected by the fastest lap.
    #expect(driver.formattedLap == "1:31.300")
}

@Test func lappedCarsKeepTheirLapText() throws {
    let driver = try racer(gap: "+2 LAPS", interval: "+1 LAP")
    #expect(driver.timingText(.interval) == "+1 LAP")
    #expect(driver.timingText(.gapToLeader) == "+2 LAPS")
}

@Test func missingFiguresShowADashInsteadOfAnotherMetrics() throws {
    let driver = try racer(gap: "+7.500", interval: nil, bestLap: nil)
    #expect(driver.timingText(.interval) == "—")
    #expect(driver.timingText(.fastestLap) == "—")
    #expect(try racer(interval: "  ").timingText(.interval) == "—")
    #expect(try racer(bestLap: 0).timingText(.fastestLap) == "—")
}

@Test func theLeaderIsCrownedOnGapsButStillGetsAFastestLap() throws {
    let leader = try racer(position: 1, gap: nil, interval: nil, bestLap: 89.25)
    #expect(TimingMetric.interval.marksLeader && TimingMetric.gapToLeader.marksLeader)
    #expect(!TimingMetric.fastestLap.marksLeader)
    #expect(leader.timingText(.fastestLap) == "1:29.250")
    #expect(leader.isLeader)
}

@Test func columnHeadingNamesTheMetricOnShow() {
    #expect(TimingMetric.allCases.map(\.title) == ["Interval", "To leader", "Fastest lap"])
    #expect(Set(TimingMetric.allCases.map(\.title)).count == 3)
}

@Test func oldBackendsWithoutTheNewFieldsStillDecode() throws {
    let json = #"{"number":4,"name":"Lando Norris","acronym":"NOR","team":"McLaren","color":"FF8000","position":2,"gap":"+1.0"}"#
    let driver = try JSONDecoder().decode(TimingDriver.self, from: Data(json.utf8))
    #expect(driver.interval == nil && driver.bestLap == nil)
    #expect(driver.timingText(.gapToLeader) == "+1.0")
    #expect(driver.timingText(.fastestLap) == "—")
}

@Test func theRowIsSpokenWithTheMetricThatIsShowing() throws {
    let driver = try racer()
    #expect(driver.accessibilitySummary(showingGap: true, metric: .interval)
            == "Position 3, Lando Norris, McLaren, 1.250 seconds behind the car ahead, last lap 1:31.300, Soft tyre")
    #expect(driver.accessibilitySummary(showingGap: true, metric: .gapToLeader)
            == "Position 3, Lando Norris, McLaren, 7.500 seconds behind the leader, last lap 1:31.300, Soft tyre")
    #expect(driver.accessibilitySummary(showingGap: true, metric: .fastestLap)
            == "Position 3, Lando Norris, McLaren, fastest lap 1:30.500, last lap 1:31.300, Soft tyre")
    #expect(try racer(bestLap: nil).spokenTiming(.fastestLap) == "fastest lap unavailable")
    #expect(try racer(position: 2, interval: "+1 LAP").spokenInterval == "1 lap behind the car ahead")
    // Without a timing column nothing is said, whatever the metric.
    #expect(!driver.accessibilitySummary(showingGap: false, metric: .fastestLap).contains("fastest"))
    // The old one-argument form still reads the gap to the leader.
    #expect(driver.accessibilitySummary(showingGap: true).contains("behind the leader"))
}
