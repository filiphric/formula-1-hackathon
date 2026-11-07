import Foundation
import Testing
@testable import FormulaCore

private func message(_ text: String, flag: String? = nil, date: String = "2026-11-07T14:00:00+00:00") -> RaceMessage {
    RaceMessage(id: text, date: date, message: text, flag: flag)
}

@Test func flagFieldMapsToTheMatchingKind() {
    #expect(message("x", flag: "RED").kind == .red)
    #expect(message("x", flag: "yellow").kind == .yellow)
    #expect(message("x", flag: "DOUBLE YELLOW").kind == .doubleYellow)
    #expect(message("x", flag: "GREEN").kind == .green)
    #expect(message("x", flag: "CLEAR").kind == .clear)
    #expect(message("x", flag: "BLUE").kind == .blue)
    #expect(message("x", flag: "CHEQUERED").kind == .chequered)
    #expect(message("x", flag: "BLACK AND WHITE").kind == .blackAndWhite)
    #expect(message("x", flag: "BLACK").kind == .black)
}

@Test func safetyCarMessagesWithoutFlagAreRecognisedAndVirtualWinsOverPlain() {
    #expect(message("SAFETY CAR DEPLOYED").kind == .safetyCar)
    #expect(message("VIRTUAL SAFETY CAR DEPLOYED").kind == .virtualSafetyCar)
    #expect(message("DRS ENABLED").kind == .info)
    #expect(message("TRACK LIMITS", flag: nil).kind == .info)
    #expect(message("anything", flag: "SOMETHING NEW").kind == .info)
}

@Test func severityRanksRedAboveYellowAboveInformation() {
    #expect(RaceControlKind.red.severity == .critical)
    #expect(RaceControlKind.black.severity == .critical)
    #expect(RaceControlKind.yellow.severity == .caution)
    #expect(RaceControlKind.safetyCar.severity == .caution)
    #expect(RaceControlKind.green.severity == .info)
    #expect(RaceControlKind.info.severity < RaceControlKind.red.severity)
}

@Test func everyKindHasADistinctLabelSoColourIsNeverTheOnlyCue() {
    let kinds: [RaceControlKind] = [.green, .clear, .yellow, .doubleYellow, .red, .blue, .blackAndWhite, .black,
                                    .chequered, .safetyCar, .virtualSafetyCar, .info]
    #expect(Set(kinds.map(\.label)).count == kinds.count)
}

@Test func messageTimestampParsesWithAndWithoutFractionalSeconds() {
    #expect(message("x", date: "2026-11-07T14:00:00+00:00").timestamp == Date(timeIntervalSince1970: 1_794_060_000))
    #expect(message("x", date: "2026-11-07T14:00:00.500Z").timestamp == Date(timeIntervalSince1970: 1_794_060_000.5))
    #expect(message("x", date: "garbage").timestamp == nil)
}

// MARK: Feed status

private func snapshot(mode: String = "live", upstream: String = "connected", updatedAt: String?) -> TimingSnapshot {
    TimingSnapshot(mode: mode, upstream: upstream, updatedAt: updatedAt, session: nil, drivers: [], messages: [], track: nil)
}

private let now = Date(timeIntervalSince1970: 1_794_060_000) // 2026-11-07T14:00:00Z

@Test func liveFeedIsLiveWithin30SecondsAndStaleAfter() {
    let fresh = FeedStatus.resolve(snapshot: snapshot(updatedAt: "2026-11-07T13:59:45Z"), connected: true, hasError: false, now: now)
    #expect(fresh.kind == .live && fresh.label == "LIVE" && !fresh.isDemo)
    let edge = FeedStatus.resolve(snapshot: snapshot(updatedAt: "2026-11-07T13:59:30Z"), connected: true, hasError: false, now: now)
    #expect(edge.kind == .live) // exactly 30 s is not yet over 30 s
    let old = FeedStatus.resolve(snapshot: snapshot(updatedAt: "2026-11-07T13:59:29Z"), connected: true, hasError: false, now: now)
    #expect(old.kind == .stale && old.label == "STALE")
}

@Test func demoIsNeverLabelledLiveOrStale() {
    let demo = FeedStatus.resolve(snapshot: snapshot(mode: "demo", upstream: "simulated", updatedAt: "2026-11-07T10:00:00Z"),
                                  connected: true, hasError: false, now: now)
    #expect(demo.label == "DEMO" && demo.isDemo)
    let dropped = FeedStatus.resolve(snapshot: snapshot(mode: "demo", upstream: "simulated", updatedAt: nil),
                                     connected: false, hasError: true, now: now)
    #expect(dropped.label == "DEMO · OFFLINE")
}

@Test func disconnectedSocketIsOfflineEvenIfLastTimingWasRecent() {
    let status = FeedStatus.resolve(snapshot: snapshot(updatedAt: "2026-11-07T13:59:59Z"), connected: false, hasError: false, now: now)
    #expect(status.kind == .offline && status.label == "OFFLINE")
    #expect(status.age == 1)
}

@Test func upstreamDisconnectOrMissingTimestampIsStaleNotLive() {
    #expect(FeedStatus.resolve(snapshot: snapshot(upstream: "reconnecting", updatedAt: "2026-11-07T13:59:59Z"),
                               connected: true, hasError: false, now: now).kind == .stale)
    #expect(FeedStatus.resolve(snapshot: snapshot(updatedAt: nil), connected: true, hasError: false, now: now).kind == .stale)
}

@Test func beforeFirstSnapshotWeAreConnectingUnlessThereWasAnError() {
    #expect(FeedStatus.resolve(snapshot: nil, connected: false, hasError: false, now: now).label == "CONNECTING")
    #expect(FeedStatus.resolve(snapshot: nil, connected: false, hasError: true, now: now).label == "OFFLINE")
}

// MARK: Spoken leaderboard rows

private func driver(position: Int?, gap: String?, lapTime: Double?, compound: String?) -> TimingDriver {
    TimingDriver(number: 1, name: "Max Verstappen", acronym: "VER", team: "Red Bull Racing", color: "3671C6",
                 position: position, gap: gap, lap: 5, lapTime: lapTime, compound: compound, location: nil)
}

@Test func leaderRowReadsAsOneSentence() {
    #expect(driver(position: 1, gap: nil, lapTime: 91.312, compound: "SOFT").accessibilitySummary
            == "Position 1, Max Verstappen, Red Bull Racing, leader, last lap 1:31.312, Soft tyre")
}

@Test func gapsAreSpokenInWords() {
    #expect(driver(position: 2, gap: "+2.431", lapTime: nil, compound: "HARD").accessibilitySummary
            == "Position 2, Max Verstappen, Red Bull Racing, 2.431 seconds behind the leader, last lap unavailable, Hard tyre")
    #expect(driver(position: 3, gap: "+1 LAP", lapTime: 90, compound: nil).spokenGap == "1 lap behind the leader")
    #expect(driver(position: 4, gap: "+2 LAPS", lapTime: 90, compound: nil).spokenGap == "2 laps behind the leader")
    #expect(driver(position: nil, gap: nil, lapTime: nil, compound: nil).accessibilitySummary
            == "Position unavailable, Max Verstappen, Red Bull Racing, gap unavailable, last lap unavailable, Tyre unknown")
}

@Test func spokenStatusNeverCallsDemoLiveAndStatesTheAgeOfStaleTiming() {
    let demo = FeedStatus.resolve(snapshot: snapshot(mode: "demo", upstream: "simulated", updatedAt: nil), connected: true, hasError: false, now: now)
    #expect(demo.spokenDescription == "Demo data. Timing is simulated, not live.")
    let live = FeedStatus.resolve(snapshot: snapshot(updatedAt: "2026-11-07T13:59:55Z"), connected: true, hasError: false, now: now)
    #expect(live.spokenDescription == "Live. Last timing 5 seconds ago.")
    let stale = FeedStatus.resolve(snapshot: snapshot(updatedAt: "2026-11-07T13:59:00Z"), connected: true, hasError: false, now: now)
    #expect(stale.spokenDescription == "Stale. No new timing for 60 seconds.")
    #expect(FeedStatus.resolve(snapshot: nil, connected: false, hasError: true, now: now).spokenDescription
            == "Offline. Not connected to the timing server.")
}
