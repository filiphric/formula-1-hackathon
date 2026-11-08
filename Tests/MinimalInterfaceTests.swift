import Foundation
import Testing
@testable import FormulaCore

@Test func iconNavigationRetainsDistinctSymbolsAndSpokenNames() {
    #expect(AppSection.live.symbol == "flag.checkered")
    #expect(AppSection.schedule.symbol == "calendar")
    #expect(AppSection.live.rawValue == "Live timing")
    #expect(AppSection.schedule.rawValue == "Schedule")
}

@Test func minimalFeedCopyKeepsExceptionsWithoutRepeatingThePill() {
    let now = TrackLayout.parseDate("2026-11-07T14:00:00Z")!
    func status(mode: String = "live", upstream: String = "connected", date: String?, connected: Bool = true) -> FeedStatus {
        FeedStatus.resolve(snapshot: TimingSnapshot(mode: mode, upstream: upstream, updatedAt: date,
            session: nil, drivers: [], messages: [], track: nil), connected: connected, hasError: false, now: now)
    }
    #expect(status(date: "2026-11-07T14:00:00Z").timingDetail == nil)
    #expect(status(date: "2026-11-07T13:22:05Z").timingDetail == "Timing 38 min old")
    #expect(status(date: nil).timingDetail == "Timing age unknown")
    let demo = status(mode: "demo", date: "2026-11-07T13:00:00Z")
    #expect(demo.timingDetail == nil)
    #expect(demo.label == "DEMO")
    let disconnected = status(mode: "demo", date: nil, connected: false)
    #expect(disconnected.label == "DEMO · OFFLINE")
    #expect(disconnected.timingDetail == "Reconnecting…")
    #expect(status(upstream: "subscribing", date: nil).timingDetail == nil)
}

@Test func connectedFeedAfterTheSessionEndsIsEndedNotStale() {
    let now = TrackLayout.parseDate("2026-11-08T16:00:00Z")!
    func status(end: String, updated: String = "2026-11-07T20:32:43Z", upstream: String = "connected") -> FeedStatus {
        FeedStatus.resolve(snapshot: TimingSnapshot(mode: "live", upstream: upstream, updatedAt: updated,
            session: RaceSession(name: "Qualifying", circuit: "Interlagos", start: "2026-11-07T19:00:00Z", end: end),
            drivers: [], messages: [], track: nil), connected: true, hasError: false, now: now)
    }
    // Opened the day after qualifying: the server is fine, there is just no session on.
    let ended = status(end: "2026-11-07T20:30:00Z")
    #expect(ended.kind == .ended)
    #expect(ended.label == "SESSION ENDED")
    #expect(ended.timingDetail == "Last timing 19 h 27 min old")
    // A session still running whose timing went quiet is genuinely stale.
    #expect(status(end: "2026-11-08T17:00:00Z").kind == .stale)
    // A fresh feed stays live even when it runs past the scheduled end.
    #expect(status(end: "2026-11-08T15:00:00Z", updated: "2026-11-08T15:59:50Z").kind == .live)
    // A server that is itself in trouble is still stale, not ended.
    #expect(status(end: "2026-11-07T20:30:00Z", upstream: "reconnecting").kind == .stale)
}

@Test func eventScreenSwipesFromRunningOrderToLiveTrackToRaceControl() {
    // The request: current order on one page, the live track on the next, race control, then team radio, then the live championship.
    #expect(DashboardPage.allCases == [.order, .track, .raceControl, .radio, .championship])
    #expect(DashboardPage.allCases.map(\.rawValue) == ["Running order", "Live track", "Race control", "Team radio", "Championship"])
    #expect(Set(DashboardPage.allCases.map(\.symbol)).count == 5)
}

@Test func swipingPastTheLastPageCyclesToTheFirstAndBack() throws {
    // The request: swiping on the last screen cycles the view. After the last page comes the first
    // again; before the first page comes the last.
    let first = try #require(DashboardPage.allCases.first)
    let last = try #require(DashboardPage.allCases.last)
    let slots = DashboardPage.loopSlots.map { DashboardPage(slot: $0) }
    #expect(slots == [last] + DashboardPage.allCases + [first])
    // Swiping forward from the last page lands on a clone of the first, which settles on the real first page.
    let pastLast = last.slot + 1
    #expect(DashboardPage.isClone(slot: pastLast))
    #expect(DashboardPage(slot: pastLast) == first)
    #expect(DashboardPage.settledSlot(pastLast) == first.slot)
    // Swiping back from the first page lands on a clone of the last.
    let beforeFirst = first.slot - 1
    #expect(DashboardPage.isClone(slot: beforeFirst))
    #expect(DashboardPage(slot: beforeFirst) == last)
    #expect(DashboardPage.settledSlot(beforeFirst) == last.slot)
    // Real pages stay where they are.
    for page in DashboardPage.allCases {
        #expect(!DashboardPage.isClone(slot: page.slot))
        #expect(DashboardPage.settledSlot(page.slot) == page.slot)
    }
}

@Test func offlineFeedWithoutAnyTimingDoesNotPromiseLastTiming() {
    let now = TrackLayout.parseDate("2026-11-07T14:00:00Z")!
    let never = FeedStatus.resolve(snapshot: nil, connected: false, hasError: true, now: now)
    #expect(never.timingDetail == "No timing received")
    let dropped = FeedStatus.resolve(snapshot: TimingSnapshot(mode: "live", upstream: "connected", updatedAt: "2026-11-07T13:59:00Z",
        session: nil, drivers: [], messages: [], track: nil), connected: false, hasError: false, now: now)
    #expect(dropped.timingDetail == "Reconnecting…")
}
