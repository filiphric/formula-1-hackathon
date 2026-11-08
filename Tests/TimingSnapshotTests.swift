import Foundation
import Testing
@testable import FormulaCore

@Test func decodesSnapshotWithMissingTimingAndLappedGap() throws {
    let data = Data(#"{"mode":"live","upstream":"connected","updatedAt":null,"session":null,"drivers":[{"number":4,"name":"Lando Norris","acronym":"NOR","team":"McLaren","color":"FF8000","position":null,"gap":"+1 LAP","lap":null,"lapTime":null,"compound":null}],"messages":[]}"#.utf8)
    let snapshot = try TimingSnapshot.decode(data)
    #expect(snapshot.drivers[0].gap == "+1 LAP")
    #expect(snapshot.drivers[0].formattedLap == "—")
}

@Test func roundsLapTimeAcrossMinuteBoundary() throws {
    let data = Data(#"{"number":4,"name":"Norris","acronym":"NOR","team":"McLaren","color":"FF8000","position":1,"gap":null,"lap":1,"lapTime":59.9998,"compound":"MEDIUM"}"#.utf8)
    let driver = try JSONDecoder().decode(TimingDriver.self, from:data)
    #expect(driver.formattedLap == "1:00.000")
}

// MARK: Cars in the pits

private func pitDriver(inPit: Bool?) -> TimingDriver {
    TimingDriver(number: 4, name: "Lando Norris", acronym: "NOR", team: "McLaren", color: "FF8000",
                 position: 2, gap: nil, lap: 3, lapTime: 91.312, compound: "SOFT", location: nil, inPit: inPit)
}

@Test func inPitDecodesFromTheBackendAndIsAbsentFromOlderOnes() throws {
    let base = #"{"number":4,"name":"Lando Norris","acronym":"NOR","team":"McLaren","color":"FF8000","position":2"#
    let pitting = try JSONDecoder().decode(TimingDriver.self, from: Data((base + #","inPit":true}"#).utf8))
    #expect(pitting.isInPit)
    let onTrack = try JSONDecoder().decode(TimingDriver.self, from: Data((base + #","inPit":false}"#).utf8))
    #expect(!onTrack.isInPit)
    let older = try JSONDecoder().decode(TimingDriver.self, from: Data((base + "}").utf8))
    #expect(!older.isInPit)
}

@Test func aCarInThePitsIsSpokenAsInThePitsAndOnlyThen() {
    #expect(pitDriver(inPit: true).accessibilitySummary(showingGap: false)
            == "Position 2, Lando Norris, McLaren, in the pits, last lap 1:31.312, Soft tyre")
    #expect(pitDriver(inPit: false).accessibilitySummary(showingGap: false)
            == "Position 2, Lando Norris, McLaren, last lap 1:31.312, Soft tyre")
    #expect(pitDriver(inPit: nil).accessibilitySummary(showingGap: false)
            == "Position 2, Lando Norris, McLaren, last lap 1:31.312, Soft tyre")
}
