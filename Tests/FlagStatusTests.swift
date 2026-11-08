import Foundation
import Testing
@testable import FormulaCore

private func decode(_ json: String) throws -> TimingSnapshot {
    try TimingSnapshot.decode(Data(json.utf8))
}

private let base = #""mode":"live","upstream":"connected","drivers":[],"messages":[]"#

// MARK: Wire contract

@Test func snapshotsFromBackendsWithoutFlagsMeanNothingIsFlagged() throws {
    let snapshot = try decode("{\(base)}")
    #expect(snapshot.flags == .clear)
    #expect(snapshot.flags.isClear)
}

@Test func decodesTheBackendsFlagStatus() throws {
    let snapshot = try decode("""
    {\(base),"flags":{"track":"safetyCar","trackSince":"2026-11-07T14:20:02+00:00",
      "sectors":[{"sector":17,"flag":"doubleYellow","since":"2026-11-07T14:20:06+00:00"},
                 {"sector":3,"flag":"yellow","since":"2026-11-07T14:21:00+00:00"}]}}
    """)
    #expect(snapshot.flags.track == .safetyCar)
    #expect(snapshot.flags.trackSince == "2026-11-07T14:20:02+00:00")
    // Lowest sector first, whatever order the server sent.
    #expect(snapshot.flags.sectors.map(\.sector) == [3, 17])
    #expect(snapshot.flags.flag(inSector: 17) == .doubleYellow)
    #expect(snapshot.flags.flag(inSector: 3) == .yellow)
    #expect(snapshot.flags.flag(inSector: 4) == nil)
    #expect(try decode(#"{\#(base),"flags":{"track":"red","trackSince":null,"sectors":[]}}"#).flags.track == .red)
    #expect(try decode(#"{\#(base),"flags":{"track":"virtualSafetyCar","sectors":[]}}"#).flags.track == .virtualSafetyCar)
}

@Test func aFlagTheAppDoesNotKnowYetNeverBreaksTheSnapshot() throws {
    let snapshot = try decode("""
    {\(base),"flags":{"track":"fullCourseYellow","sectors":[{"sector":5,"flag":"purple"},
      {"sector":6,"flag":"yellow"},{"flag":"yellow"},{"sector":0,"flag":"yellow"}]}}
    """)
    #expect(snapshot.flags.track == .clear)
    #expect(snapshot.flags.sectors.map(\.sector) == [6])
    // Wrongly typed flags are dropped the same way, and the rest of the snapshot is untouched.
    let wrong = try decode(#"{\#(base),"flags":"red"}"#)
    #expect(wrong.flags == .clear)
    #expect(wrong.mode == "live")
}

@Test func flagStatusRoundTripsThroughJSON() throws {
    let status = FlagStatus(track: .red, trackSince: "2026-11-07T18:02:23+00:00",
                            sectors: [SectorFlag(sector: 9, flag: .doubleYellow, since: "2026-11-07T18:03:00+00:00")])
    let decoded = try JSONDecoder().decode(FlagStatus.self, from: JSONEncoder().encode(status))
    #expect(decoded == status)
}

// MARK: What the banner says

@Test func nothingFlaggedHasNoLines() {
    #expect(FlagStatus.clear.lines.isEmpty)
    #expect(FlagStatus.clear.spokenDescription == "")
}

@Test func theBannerListsTheTrackFirstThenDoubleYellowsThenYellows() {
    let status = FlagStatus(track: .safetyCar, sectors: [
        SectorFlag(sector: 3, flag: .yellow), SectorFlag(sector: 13, flag: .doubleYellow),
        SectorFlag(sector: 12, flag: .doubleYellow), SectorFlag(sector: 4, flag: .yellow),
    ])
    #expect(status.lines.map(\.text) == ["Safety car", "Double yellow · sectors 12, 13", "Yellow · sectors 3, 4"])
    #expect(status.lines.map(\.kind) == [.safetyCar, .doubleYellow, .yellow])
}

@Test func oneFlaggedSectorIsSingular() {
    let status = FlagStatus(sectors: [SectorFlag(sector: 7, flag: .yellow)])
    #expect(status.lines.map(\.text) == ["Yellow · sector 7"])
    #expect(!status.isClear)
}

@Test func eachTrackWideConditionHasItsOwnWordsSoColourIsNeverTheOnlyCue() {
    #expect(FlagStatus(track: .red).lines.map(\.text) == ["Red flag"])
    #expect(FlagStatus(track: .safetyCar).lines.map(\.text) == ["Safety car"])
    #expect(FlagStatus(track: .virtualSafetyCar).lines.map(\.text) == ["Virtual safety car"])
    #expect(Set([TrackFlag.red, .safetyCar, .virtualSafetyCar].map(\.label)).count == 3)
}

@Test func spokenDescriptionReadsAsSentences() {
    let status = FlagStatus(track: .red, sectors: [
        SectorFlag(sector: 12, flag: .doubleYellow), SectorFlag(sector: 13, flag: .doubleYellow),
    ])
    #expect(status.spokenDescription == "Red flag. Double yellow in sectors 12, 13.")
}

// MARK: When flags are shown

private func session(mode: String = "live", end: String = "2026-11-07T19:00:00Z", locationDate: String? = nil) throws -> TimingSnapshot {
    let location = locationDate.map { #","location":{"x":1,"y":2,"date":"\#($0)"}"# } ?? ""
    return try decode("""
    {"mode":"\(mode)","upstream":"connected",
     "session":{"name":"Qualifying","circuit":"Interlagos","start":"2026-11-07T18:00:00Z","end":"\(end)"},
     "drivers":[{"number":4,"name":"Norris","acronym":"NOR","team":"McLaren","color":"FF8000"\(location)}],
     "messages":[],"flags":{"track":"red","sectors":[{"sector":2,"flag":"yellow"}]}}
    """)
}

@Test func flagsAreShownWhileTheSessionRuns() throws {
    let now = try #require(TrackLayout.parseDate("2026-11-07T18:30:00Z"))
    #expect(try session().activeFlags(at: now).track == .red)
}

@Test func flagsOfAFinishedSessionWithNoCarOnTrackAreHistory() throws {
    let now = try #require(TrackLayout.parseDate("2026-11-07T21:00:00Z"))
    #expect(try session().activeFlags(at: now).isClear)
    #expect(try session(locationDate: "2026-11-07T18:30:00Z").activeFlags(at: now).isClear)
}

@Test func aRedFlagThatRunsPastTheScheduledEndIsStillShownWhileCarsReport() throws {
    let now = try #require(TrackLayout.parseDate("2026-11-07T19:10:00Z"))
    #expect(try session(locationDate: "2026-11-07T19:09:58Z").activeFlags(at: now).track == .red)
}

@Test func demoFlagsAreAlwaysShown() throws {
    let now = try #require(TrackLayout.parseDate("2030-01-01T00:00:00Z"))
    #expect(try session(mode: "demo").activeFlags(at: now).track == .red)
}

// MARK: Colour

@Test func theSectorNumberIsReadableOnTheYellowBadgeAndTheYellowShowsOnTheTrack() {
    #expect(RacingPalette.onStatus.contrastRatio(with: RacingPalette.flagYellow) >= 4.5)
    #expect(RacingPalette.flagYellow.contrastRatio(with: RacingPalette.trackSurface) >= 3)
}
