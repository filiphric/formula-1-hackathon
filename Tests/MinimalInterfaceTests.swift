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
