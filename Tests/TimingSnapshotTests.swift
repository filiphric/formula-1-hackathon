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
