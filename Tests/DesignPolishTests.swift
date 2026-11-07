import Foundation
import Testing
@testable import FormulaCore

// Expected values in this file come from the P-90 polish requirements, not from the code.

// MARK: 1. Humanised durations

@Test func durationsUnderAMinuteAreSeconds() {
    #expect(DurationText.compact(seconds: 0) == "0 s")
    #expect(DurationText.compact(seconds: 45) == "45 s")
    #expect(DurationText.compact(seconds: 59) == "59 s")
}

@Test func durationsFromAMinuteToAnHourAreMinutes() {
    #expect(DurationText.compact(seconds: 60) == "1 min")
    #expect(DurationText.compact(seconds: 2_275) == "38 min")   // the header that used to say "2,275 seconds"
    #expect(DurationText.compact(seconds: 3_540) == "59 min")
}

@Test func durationsNeverReadSixtyMinutesOrTwentyFourHours() {
    #expect(DurationText.compact(seconds: 3_599) == "1 h")      // 59.98 min is an hour, not "60 min"
    #expect(DurationText.compact(seconds: 3_600) == "1 h")
    #expect(DurationText.compact(seconds: 86_399) == "1 d")     // not "24 h"
}

@Test func durationsOverAnHourCombineHoursAndMinutes() {
    #expect(DurationText.compact(seconds: 4_320) == "1 h 12 min")
    #expect(DurationText.compact(seconds: 2 * 3_600) == "2 h")
}

@Test func durationsOverADayAreDaysAndHours() {
    #expect(DurationText.compact(seconds: 86_400) == "1 d")
    #expect(DurationText.compact(seconds: 86_400 + 2 * 3_600) == "1 d 2 h")
    #expect(DurationText.compact(seconds: 3 * 86_400) == "3 d")
}

@Test func negativeOrNonFiniteDurationsClampToZero() {
    #expect(DurationText.compact(seconds: -5) == "0 s")
    #expect(DurationText.compact(seconds: .nan) == "0 s")
}

private func feedSnapshot(updatedAt: String) -> TimingSnapshot {
    TimingSnapshot(mode: "live", upstream: "connected", updatedAt: updatedAt, session: nil, drivers: [], messages: [], track: nil)
}

@Test func headerAndSpokenStalenessUseTheSameHumanText() {
    let now = TrackLayout.parseDate("2026-11-07T14:00:00Z")!
    // 2,275 s before `now`.
    let updated = ISO8601DateFormatter().string(from: now.addingTimeInterval(-2_275))
    let status = FeedStatus.resolve(snapshot: feedSnapshot(updatedAt: updated), connected: true, hasError: false, now: now)
    #expect(status.kind == .stale)
    #expect(status.ageText == "38 min")
    #expect(status.spokenDescription == "Stale. No new timing for 38 min.")
    let hour = FeedStatus.resolve(snapshot: feedSnapshot(updatedAt: ISO8601DateFormatter().string(from: now.addingTimeInterval(-4_320))),
                                  connected: true, hasError: false, now: now)
    #expect(hour.spokenDescription == "Stale. No new timing for 1 h 12 min.")
    #expect(FeedStatus.resolve(snapshot: nil, connected: false, hasError: false, now: now).ageText == nil)
}

// MARK: 2. Gap column only when gaps exist

private func gapDriver(_ position: Int, gap: String?) -> TimingDriver {
    TimingDriver(number: position, name: "D\(position)", acronym: "D\(position)", team: "T", color: "FFFFFF",
                 position: position, gap: gap, lap: 1, lapTime: 90, compound: nil, location: nil)
}

@Test func gapColumnNeedsAtLeastTwoDriversWithAGap() {
    let none = (1...5).map { gapDriver($0, gap: nil) }
    #expect(!none.hasUsableGaps)
    // One trailing driver with a gap is enough on a two-driver board: the leader has none to show.
    #expect([gapDriver(1, gap: nil), gapDriver(2, gap: "+1.2")].hasUsableGaps)
    #expect(![gapDriver(1, gap: nil), gapDriver(2, gap: nil)].hasUsableGaps)
    // A single stray gap among many drivers is still noise.
    #expect(!([gapDriver(1, gap: nil), gapDriver(2, gap: "+1.2")] + (3...20).map { gapDriver($0, gap: nil) }).hasUsableGaps)
    #expect(![gapDriver(1, gap: nil), gapDriver(2, gap: "+1.2"), gapDriver(3, gap: "  ")].hasUsableGaps)
    #expect([gapDriver(1, gap: nil), gapDriver(2, gap: "+1.2"), gapDriver(3, gap: "+3.4")].hasUsableGaps)
    #expect(![TimingDriver]().hasUsableGaps)
}

@Test func withoutGapsEveryLayoutDropsGapAndKeepsLastLap() {
    for layout in TimingLayout.allCases {
        #expect(!layout.columns(showingGap: false).contains(.gap))
        #expect(layout.columns(showingGap: false).contains(.lastLap))
    }
    // Compact normally drops LAST LAP; with no gap it is the only timing figure, so it stays.
    #expect(TimingLayout.compact.columns(showingGap: false) == [.position, .driver, .lastLap, .tyre])
}

// MARK: Team fills the room the GAP column leaves

@Test func withoutGapsTeamShowsWheneverThereIsRoomForIt() {
    // Requirement: once GAP is dropped, the empty stretch beside the driver code shows the team,
    // at every width that is not the narrowest.
    #expect(TimingLayout.wide.columns(showingGap: false) == [.position, .driver, .team, .lastLap, .tyre])
    #expect(TimingLayout.standard.columns(showingGap: false) == [.position, .driver, .team, .lastLap, .tyre])
}

@Test func withoutGapsTheNarrowestLayoutStillDropsTeamBeforeScrolling() {
    #expect(!TimingLayout.compact.columns(showingGap: false).contains(.team))
}

@Test func withGapsTeamStillDropsAtStandardWidth() {
    // The existing drop order with a GAP column is untouched.
    #expect(TimingLayout.standard.columns(showingGap: true) == [.position, .driver, .gap, .lastLap, .tyre])
    #expect(TimingLayout.compact.columns(showingGap: true) == [.position, .driver, .gap, .tyre])
}

@Test func onlyTheWidestLayoutNeedsRoomForTheFullTeamName() {
    // Wide shows the whole name; the layouts below it let the name truncate to fit.
    #expect(TimingLayout.wide.showsFullTeamName)
    #expect(!TimingLayout.standard.showsFullTeamName)
    #expect(!TimingLayout.compact.showsFullTeamName)
}

@Test func withGapsLayoutsAreUnchanged() {
    for layout in TimingLayout.allCases { #expect(layout.columns(showingGap: true) == layout.columns) }
}

// MARK: 3. Feed pill only on Live timing

@Test func onlyTheLiveSectionShowsTheFeedStatus() {
    #expect(AppSection.live.showsFeedStatus)
    #expect(!AppSection.schedule.showsFeedStatus)
    #expect(AppSection.allCases.map(\.rawValue) == ["Live timing", "Schedule"])
}

// MARK: 4. Calendar opens on the next race

private func race(_ round: Int, start: String) -> RaceWeekend {
    let day = String(start.prefix(10))
    let object: [String: Any] = ["round": round, "name": "GP \(round)", "circuit": "C", "country": "X",
                                 "sessions": [["name": "Race", "date": day, "start": start]]]
    return try! JSONDecoder().decode(RaceWeekend.self, from: JSONSerialization.data(withJSONObject: object))
}

private func season(_ races: [RaceWeekend]) -> RaceSchedule {
    RaceSchedule(season: 2027, mode: "live", source: "t", fetchedAt: "2027-03-10T10:00:00Z", stale: false, races: races)
}

private let today = TrackLayout.parseDate("2027-03-10T10:00:00Z")!
// Rounds 1–6 are past, 7 is next, 8–9 are later.
private let midSeason = season((1...6).map { race($0, start: "2027-02-\(String(format: "%02d", $0))T14:00:00Z") }
                               + [race(7, start: "2027-03-14T14:00:00Z"), race(8, start: "2027-04-14T14:00:00Z"), race(9, start: "2027-05-14T14:00:00Z")])
private let finished = season((1...3).map { race($0, start: "2027-02-0\($0)T14:00:00Z") })

@Test func calendarDefaultsToUpcomingWhileRacesRemainAndAllOnceTheSeasonIsOver() {
    #expect(midSeason.defaultFilter(at: today) == .upcoming)
    #expect(finished.defaultFilter(at: today) == .all)
    #expect(season([]).defaultFilter(at: today) == .all)
}

@Test func filtersSelectPastOrUpcomingRaces() {
    #expect(midSeason.races(matching: .all, at: today).map(\.round) == Array(1...9))
    #expect(midSeason.races(matching: .upcoming, at: today).map(\.round) == [7, 8, 9])
    #expect(midSeason.races(matching: .past, at: today).map(\.round) == Array(1...6))
}

@Test func calendarFocusesTheNextRaceNotTheSixPastOnesAbovePast() {
    #expect(midSeason.calendarFocus(for: .all, at: today) == .nextRace(round: 7))
    #expect(midSeason.calendarFocus(for: .upcoming, at: today) == .nextRace(round: 7))
    // Past-only list does not contain the next race: stay at the top.
    #expect(midSeason.calendarFocus(for: .past, at: today) == .top)
}

@Test func aFinishedSeasonFocusesTheLastRaceAndSaysSeasonComplete() {
    #expect(finished.calendarFocus(for: .all, at: today) == .seasonComplete(lastRound: 3))
    #expect(finished.calendarFocus(for: .past, at: today) == .seasonComplete(lastRound: 3))
    #expect(finished.calendarFocus(for: .upcoming, at: today) == .top)   // nothing to show
    #expect(season([]).calendarFocus(for: .all, at: today) == .top)
}

// MARK: 5. Date ranges on one line, no weekday names

private func weekend(sessionDates: [String], zone: String? = nil) -> RaceWeekend {
    let sessions = sessionDates.map { ["name": "S", "date": $0] }
    let object: [String: Any] = ["round": 1, "name": "GP", "circuit": "C", "country": "X", "sessions": sessions]
    return try! JSONDecoder().decode(RaceWeekend.self, from: JSONSerialization.data(withJSONObject: object))
}

private let utc = TimeZone(identifier: "UTC")!
private let us = Locale(identifier: "en_US")

@Test func sameMonthRangeIsMonthThenDaysWithAnEnDash() {
    #expect(weekend(sessionDates: ["2027-03-06", "2027-03-07", "2027-03-08"]).dateRange(timeZone: utc, locale: us) == "Mar 6–8")
}

@Test func rangeAcrossMonthsNamesBothMonths() {
    #expect(weekend(sessionDates: ["2027-06-28", "2027-07-01"]).dateRange(timeZone: utc, locale: us) == "Jun 28 – Jul 1")
}

@Test func rangeAcrossNewYearAndSingleDay() {
    #expect(weekend(sessionDates: ["2027-12-30", "2028-01-02"]).dateRange(timeZone: utc, locale: us) == "Dec 30 – Jan 2")
    #expect(weekend(sessionDates: ["2027-03-14"]).dateRange(timeZone: utc, locale: us) == "Mar 14")
    #expect(weekend(sessionDates: []).dateRange(timeZone: utc, locale: us) == nil)
}

@Test func dayFirstLocalesReadDaysThenMonth() {
    #expect(weekend(sessionDates: ["2027-03-06", "2027-03-08"]).dateRange(timeZone: utc, locale: Locale(identifier: "en_GB")) == "6–8 Mar")
}

@Test func dateRangesNeverContainWeekdayNames() {
    let text = weekend(sessionDates: ["2027-03-06", "2027-03-08"]).dateRange(timeZone: utc, locale: us) ?? ""
    for day in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] { #expect(!text.contains(day)) }
}

// MARK: 6. Track map

private func trackSnapshot(locationDates: [String?], end: String = "2026-11-06T13:00:00Z", upstream: String = "connected") -> TimingSnapshot {
    let drivers = locationDates.enumerated().map { index, date -> TimingDriver in
        let location = date.map { DriverLocation(x: 1, y: 2, date: $0) }
        return TimingDriver(number: index + 1, name: "D", acronym: "D", team: "T", color: "FFFFFF", position: index + 1, gap: nil,
                            lap: nil, lapTime: nil, compound: nil, location: location)
    }
    return TimingSnapshot(mode: "live", upstream: upstream, updatedAt: nil,
                          session: RaceSession(name: "Q", circuit: "C", start: "2026-11-06T12:00:00Z", end: end),
                          drivers: drivers, messages: [], track: nil)
}

private let after = TrackLayout.parseDate("2026-11-06T14:00:00Z")!
private let oldFix = "2026-11-06T12:30:00Z"      // 90 minutes old at `after`
private let freshFix = "2026-11-06T13:59:58Z"    // 2 seconds old at `after`

@Test func allStaleOnlyWhenEveryKnownPositionIsOldAndThereIsAtLeastOne() {
    #expect(trackSnapshot(locationDates: [oldFix, oldFix, oldFix]).allPositionsStale(at: after))
    #expect(!trackSnapshot(locationDates: [oldFix, freshFix, oldFix]).allPositionsStale(at: after))   // some stale: keep dimming
    #expect(!trackSnapshot(locationDates: [freshFix, freshFix]).allPositionsStale(at: after))
    #expect(!trackSnapshot(locationDates: []).allPositionsStale(at: after))
    #expect(!trackSnapshot(locationDates: [nil, nil]).allPositionsStale(at: after))                   // no positions at all
    #expect(trackSnapshot(locationDates: [nil, oldFix]).allPositionsStale(at: after))                 // unlocated drivers don't count
}

@Test func endedSessionWithOldPositionsShowsTheNotLiveCaption() {
    #expect(trackSnapshot(locationDates: [oldFix, oldFix]).positionsNotLiveCaption(at: after, connected: true)
            == "Session ended · positions not live")
    #expect(trackSnapshot(locationDates: [oldFix, freshFix]).positionsNotLiveCaption(at: after, connected: true) == nil)
}

@Test func captionNamesDisconnectOrJustNotLiveWhenTheSessionHasNotEnded() {
    let during = TrackLayout.parseDate("2026-11-06T12:45:00Z")!
    #expect(trackSnapshot(locationDates: [oldFix]).positionsNotLiveCaption(at: during, connected: false) == "Disconnected · positions not live")
    #expect(trackSnapshot(locationDates: ["2026-11-06T12:00:30Z"], upstream: "reconnecting").positionsNotLiveCaption(at: during, connected: true)
            == "Disconnected · positions not live")
    #expect(trackSnapshot(locationDates: ["2026-11-06T12:00:30Z"]).positionsNotLiveCaption(at: during, connected: true) == "Positions not live")
}

private func distance(_ a: TrackPoint, _ b: TrackPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }

@Test func markersAlreadyApartAreLeftWhereTheyAre() {
    let points = [TrackPoint(x: 10, y: 10), TrackPoint(x: 100, y: 10), TrackPoint(x: 10, y: 100)]
    #expect(MarkerSpread.separated(points, minDistance: 28) == points)
}

@Test func twentyTwoMarkersOnOneSpotEndUpAtLeastOneMarkerApart() {
    let pile = Array(repeating: TrackPoint(x: 200, y: 150), count: 22)
    let spread = MarkerSpread.separated(pile, minDistance: 28)
    #expect(spread.count == 22)
    #expect(spread[0] == pile[0])                     // the first (leader) keeps the true position
    for i in 0..<spread.count {
        for j in (i + 1)..<spread.count { #expect(distance(spread[i], spread[j]) >= 28 - 1e-6, "markers \(i) and \(j) overlap") }
    }
}

@Test func spreadIsDeterministicAndStaysInsideTheMap() {
    let pile = Array(repeating: TrackPoint(x: 20, y: 20), count: 8)
    let bounds = MarkerLabelPlacement.Rect(x: 0, y: 0, width: 300, height: 200)
    let first = MarkerSpread.separated(pile, minDistance: 28, bounds: bounds)
    #expect(first == MarkerSpread.separated(pile, minDistance: 28, bounds: bounds))
    for point in first { #expect(point.x >= 0 && point.x <= 300 && point.y >= 0 && point.y <= 200) }
}

@Test func trackAspectRatioIsWidthOverHeightOfTheCircuit() throws {
    let wide = try JSONDecoder().decode(TrackLayout.self, from: Data(#"{"source":"t","points":[{"x":0,"y":0},{"x":300,"y":100}]}"#.utf8))
    #expect(wide.aspectRatio == 3)
    let flat = try JSONDecoder().decode(TrackLayout.self, from: Data(#"{"source":"t","points":[{"x":1,"y":1},{"x":1,"y":1}]}"#.utf8))
    #expect(flat.aspectRatio == nil)
}

// MARK: VoiceOver rows follow the visible columns

@Test func spokenRowOmitsTheGapWhenTheGapColumnIsHidden() {
    let driver = TimingDriver(number: 4, name: "Lando Norris", acronym: "NOR", team: "McLaren", color: "FF8000",
                              position: 2, gap: nil, lap: 3, lapTime: 91.312, compound: "SOFT", location: nil)
    #expect(driver.accessibilitySummary(showingGap: false) == "Position 2, Lando Norris, McLaren, last lap 1:31.312, Soft tyre")
    #expect(driver.accessibilitySummary(showingGap: true) == "Position 2, Lando Norris, McLaren, gap unavailable, last lap 1:31.312, Soft tyre")
}

@Test func newestPositionAgeIsMeasuredFromTheFreshestFix() {
    let snapshot = trackSnapshot(locationDates: ["2026-11-06T12:00:00Z", "2026-11-06T13:00:00Z", nil])
    #expect(snapshot.newestPositionAge(at: TrackLayout.parseDate("2026-11-06T14:00:00Z")!) == 3_600)
    #expect(trackSnapshot(locationDates: [nil]).newestPositionAge(at: after) == nil)
}

// MARK: Round and country eyebrow never wraps a separator onto a new line

@Test func roundEyebrowIsOneLineNormallyAndTwoLinesWithoutSeparatorWhenStacked() {
    let object: [String: Any] = ["round": 20, "name": "Brazilian Grand Prix", "circuit": "Interlagos", "country": "Brazil",
                                 "sessions": [["name": "Race", "date": "2026-11-08", "start": "2026-11-08T18:00:00Z"]]]
    let brazil = try! JSONDecoder().decode(RaceWeekend.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(brazil.roundLines(stacked: false) == ["Round 20 · Brazil"])
    #expect(brazil.roundLines(stacked: true) == ["Round 20", "Brazil"])
    #expect(brazil.roundLines(stacked: true).allSatisfy { !$0.contains("·") && !$0.hasPrefix(" ") })
}
