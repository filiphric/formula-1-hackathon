import Foundation
import Testing
@testable import FormulaCore

private func clip(_ url: String?, driver: Int = 1, date: String = "2026-11-07T14:00:05+00:00") -> TeamRadio {
    TeamRadio(id: "\(date):\(driver)", date: date, driverNumber: driver, recordingUrl: url)
}

private func snapshot(mode: String = "live", upstream: String = "connected", radios: [TeamRadio] = []) -> TimingSnapshot {
    TimingSnapshot(mode: mode, upstream: upstream, updatedAt: nil, session: nil, drivers: [], messages: [], track: nil, radios: radios)
}

@Test func backendJSONDecodesRadiosWithCamelCaseKeysNewestFirst() throws {
    let json = """
    {"mode":"live","upstream":"connected","updatedAt":null,"session":null,"drivers":[],"messages":[],"track":null,
     "radios":[{"id":"b","date":"2026-11-07T14:00:09+00:00","driverNumber":16,"recordingUrl":"https://example.com/b.mp3"},
               {"id":"a","date":"2026-11-07T14:00:01+00:00","driverNumber":4,"recordingUrl":null}]}
    """
    let decoded = try TimingSnapshot.decode(Data(json.utf8))
    #expect(decoded.radios.map(\.driverNumber) == [16, 4])
    #expect(decoded.radios[0].playbackURL == URL(string: "https://example.com/b.mp3"))
    #expect(decoded.radios[1].playbackURL == nil)
}

@Test func anOlderServerWithoutRadiosStillDecodes() throws {
    let json = #"{"mode":"live","upstream":"connected","updatedAt":null,"session":null,"drivers":[],"messages":[]}"#
    #expect(try TimingSnapshot.decode(Data(json.utf8)).radios.isEmpty)
}

@Test func onlyPlainHttpsRecordingsAreEverPlayed() {
    #expect(clip("https://livetiming.formula1.com/static/a.mp3").playbackURL != nil)
    for bad in ["http://example.com/a.mp3", "file:///etc/passwd", "https:///a.mp3", "https://u:p@example.com/a.mp3",
                "javascript:alert(1)", "not a url", ""] {
        #expect(clip(bad).playbackURL == nil, "\(bad) must not be playable")
    }
    #expect(clip(nil).playbackURL == nil)
}

@Test func aRealOpenF1RecordingLinkWithAccentedFolderNamesIsPlayable() {
    // Copied from OpenF1's /team_radio for the 2026 São Paulo Grand Prix.
    let url = "https://livetiming.formula1.com/static/2026/2026-11-08_São_Paulo_Grand_Prix/2026-11-07_Qualifying/TeamRadio/ALB_23_20261107_145514.mp3"
    #expect(clip(url).playbackURL != nil)
}

@Test func theRadioFeedIsLabelledDemoLiveEndedOrDisconnected() {
    let now = TrackLayout.parseDate("2026-11-07T19:30:00Z")!
    let during = RaceSession(name: "Qualifying", circuit: "Interlagos", start: "2026-11-07T18:00:00Z", end: "2026-11-07T20:00:00Z")
    let over = RaceSession(name: "Qualifying", circuit: "Interlagos", start: "2026-11-07T16:00:00Z", end: "2026-11-07T17:00:00Z")
    func feed(_ session: RaceSession?, mode: String = "live", upstream: String = "connected", radios: [TeamRadio] = []) -> TimingSnapshot {
        TimingSnapshot(mode: mode, upstream: upstream, updatedAt: nil, session: session, drivers: [], messages: [], track: nil, radios: radios)
    }
    let clips = [clip("https://example.com/a.mp3")]
    #expect(feed(during, mode: "demo").radioStatus(connected: true, now: now).hasPrefix("DEMO"))
    #expect(feed(during, radios: clips).radioStatus(connected: true, now: now).hasPrefix("LIVE"))
    #expect(feed(during).radioStatus(connected: true, now: now) == "Waiting for team radio")
    #expect(feed(over, radios: clips).radioStatus(connected: true, now: now).hasPrefix("Session ended"))
    #expect(feed(over).radioStatus(connected: true, now: now) == "Session ended · No team radio")
    #expect(feed(during, radios: clips).radioStatus(connected: false, now: now).hasPrefix("Disconnected"))
    #expect(feed(during, upstream: "reconnecting").radioStatus(connected: true, now: now).hasPrefix("Disconnected"))
}

@Test func aClipSpeaksTheDriverAndWhetherItHasAudio() {
    let spoken = clip(nil).accessibilitySummary(driver: nil, timeText: "2:00:05 PM")
    #expect(spoken == "Team radio, Driver 1, 2:00:05 PM, No audio available")
    #expect(clip("https://example.com/a.mp3").accessibilitySummary(driver: nil, timeText: nil) == "Team radio, Driver 1")
}

@Test func waveformIsStableBoundedAndDiffersBetweenClips() {
    let a = TeamRadio.waveform(seed: "a", bars: 32)
    #expect(a.count == 32)
    #expect(a == TeamRadio.waveform(seed: "a", bars: 32))
    #expect(a != TeamRadio.waveform(seed: "b", bars: 32))
    #expect(a.allSatisfy { (0.25...1.0).contains($0) })
    #expect(TeamRadio.waveform(seed: "a", bars: 0).isEmpty)
}
