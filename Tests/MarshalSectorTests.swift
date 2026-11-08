import Foundation
import Testing
@testable import FormulaCore

/// A square lap recorded from the bottom-left corner, anticlockwise: 100 along each side, 400 in all.
private let square = [(0.0, 0.0), (100, 0), (100, 100), (0, 100), (0, 0)].map { TrackPoint(x: $0.0, y: $0.1) }

private func point(_ x: Double, _ y: Double) -> TrackPoint { TrackPoint(x: x, y: y) }

// MARK: Placing sectors on an outline

@Test func eachSectorRunsFromItsStartToTheNextSectorsStart() throws {
    // Starts at the middle of each side: 50, 150, 250 and 350 units into the lap.
    let starts = [point(50, 0), point(100, 50), point(50, 100), point(0, 50)]
    let sectors = try #require(MarshalSectors.runs(starts: starts, along: square))
    #expect(sectors.count == 4)
    #expect(sectors.points(forSector: 1) == [[point(50, 0), point(100, 0), point(100, 50)]])
    #expect(sectors.points(forSector: 2) == [[point(100, 50), point(100, 100), point(50, 100)]])
    #expect(sectors.points(forSector: 3) == [[point(50, 100), point(0, 100), point(0, 50)]])
}

@Test func theLastSectorRunsAcrossTheStartLineIntoTwoPieces() throws {
    let starts = [point(50, 0), point(100, 50), point(50, 100), point(0, 50)]
    let sectors = try #require(MarshalSectors.runs(starts: starts, along: square))
    // Sector 4 starts 350 units in, passes the point where the lap was recorded from, and ends 50 in.
    #expect(sectors.points(forSector: 4) == [[point(0, 50), point(0, 0)], [point(0, 0), point(50, 0)]])
}

@Test func aSectorSpanningTheRecordedStartIsFoundWhereverTheLapWasRecordedFrom() throws {
    // Sector 1 starts before the recorded start, so sector 2 is the first one met along the outline.
    let starts = [point(0, 50), point(50, 0), point(100, 50), point(50, 100)]
    let sectors = try #require(MarshalSectors.runs(starts: starts, along: square))
    #expect(sectors.points(forSector: 1) == [[point(0, 50), point(0, 0)], [point(0, 0), point(50, 0)]])
    #expect(sectors.points(forSector: 2) == [[point(50, 0), point(100, 0), point(100, 50)]])
    #expect(sectors.points(forSector: 4) == [[point(50, 100), point(0, 100), point(0, 50)]])
}

@Test func startsThatDoNotRunOnceAroundTheOutlineInOrderAreRejected() {
    // Same places, but numbered against the direction of travel.
    #expect(MarshalSectors.runs(starts: [point(0, 50), point(50, 100), point(100, 50), point(50, 0)], along: square) == nil)
    // Two sectors start in the same place.
    #expect(MarshalSectors.runs(starts: [point(50, 0), point(50, 0), point(50, 100)], along: square) == nil)
    // Out of order.
    #expect(MarshalSectors.runs(starts: [point(50, 0), point(50, 100), point(100, 50), point(0, 50)], along: square) == nil)
}

@Test func startsFarFromTheOutlineAreRejected() {
    // Sector 3 is nowhere near this circuit: a different layout or coordinate frame.
    #expect(MarshalSectors.runs(starts: [point(50, 0), point(100, 50), point(400, 400), point(0, 50)], along: square) == nil)
    // A start a little off the line, as the published and the recorded lap differ slightly, is fine.
    #expect(MarshalSectors.runs(starts: [point(50, 2), point(102, 50), point(50, 98), point(-1, 50)], along: square) != nil)
}

@Test func tooFewStartsOrTooShortAnOutlineGiveNothing() {
    #expect(MarshalSectors.runs(starts: [point(50, 0), point(100, 50)], along: square) == nil)
    #expect(MarshalSectors.runs(starts: [point(0, 0), point(1, 0), point(2, 0)], along: [point(0, 0)]) == nil)
    #expect(MarshalSectors.runs(starts: [point(.nan, 0), point(100, 50), point(50, 100)], along: square) == nil)
}

@Test func theDemoCircuitIsSplitIntoEqualLengths() throws {
    let sectors = try #require(MarshalSectors.evenRuns(count: 4, along: square))
    #expect(sectors.count == 4)
    #expect(sectors.points(forSector: 1) == [[point(0, 0), point(100, 0)]])
    #expect(sectors.points(forSector: 2) == [[point(100, 0), point(100, 100)]])
    #expect(sectors.points(forSector: 4) == [[point(0, 100), point(0, 0)]])
    #expect(MarshalSectors.evenRuns(count: 2, along: square) == nil)
}

// MARK: Real circuit

private func interlagos() throws -> TrackLayout {
    let url = try #require(Bundle.module.url(forResource: "interlagos-track", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(TrackLayout.self, from: Data(contentsOf: url))
}

private func length(_ run: [TrackPoint]) -> Double {
    zip(run, run.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
}

@Test func interlagosHasItsSixteenMarshalSectorsOnTheRecordedLap() throws {
    // Race control flagged sectors up to 16 at Interlagos in the 2026 São Paulo weekend, and never above.
    let track = try interlagos()
    let sectors = try #require(track.sectorRuns(circuit: "Interlagos", isDemo: false))
    #expect(sectors.count == 16)
    for number in 1...16 { #expect(!sectors.points(forSector: number).isEmpty, "sector \(number) has no track") }
    #expect(sectors.points(forSector: 17).isEmpty)
}

@Test func interlagosSectorsTileTheWholeLapWithoutGapsOrOverlap() throws {
    let track = try interlagos()
    let sectors = try #require(track.sectorRuns(circuit: "Interlagos", isDemo: false))
    // Together the sectors are exactly the recorded lap, so their lengths add up to the outline's.
    let total = (1...16).flatMap { sectors.points(forSector: $0) }.reduce(0) { $0 + length($1) }
    let lap = length(track.points)
    #expect(abs(total - lap) < lap * 0.0001)
    // And each sector begins where the one before it ends. Race control flagged 16 and 1 together in
    // qualifying, so these two in particular must be neighbours across the start line.
    for number in 1...16 {
        let end = try #require(sectors.points(forSector: number).last?.last)
        let next = try #require(sectors.points(forSector: number % 16 + 1).first?.first)
        #expect(hypot(end.x - next.x, end.y - next.y) < 0.000_001, "sector \(number) does not meet sector \(number % 16 + 1)")
    }
}

@Test func sectorsOfACircuitThatIsNotInTheTableAreUnknownRatherThanGuessed() throws {
    let track = try interlagos()
    #expect(track.sectorRuns(circuit: "Madring", isDemo: false) == nil)
    #expect(track.sectorRuns(circuit: nil, isDemo: false) == nil)
    // The Interlagos table must not be applied to another circuit's outline.
    #expect(try trackOfAnotherCircuit().sectorRuns(circuit: "Interlagos", isDemo: false) == nil)
}

private func trackOfAnotherCircuit() throws -> TrackLayout {
    // A 3000 x 2000 loop well away from Interlagos' coordinates.
    let ring = (0...40).map { i -> TrackPoint in
        let angle = Double(i) / 40 * 2 * .pi
        return TrackPoint(x: 20_000 + 1500 * cos(angle), y: 20_000 + 1000 * sin(angle))
    }
    return TrackLayout(source: "test", points: ring)
}

@Test func demoTimingUsesItsEvenSplitAndLiveTimingDoesNot() throws {
    let ring = try trackOfAnotherCircuit()
    #expect(ring.sectorRuns(circuit: "Demo Grand Prix", isDemo: true)?.count == 12)
    #expect(ring.sectorRuns(circuit: "Demo Grand Prix", isDemo: false) == nil)
}

@Test func theGeneratedTableCoversEachPublishedCircuitWithSensibleStarts() throws {
    for name in MarshalSectorData.starts.keys {
        let starts = try #require(MarshalSectors.starts(forCircuit: name), "\(name) has no parseable starts")
        #expect(starts.count >= 10 && starts.count <= 30, "\(name) has \(starts.count) sectors")
    }
    #expect(MarshalSectors.starts(forCircuit: " Interlagos \n")?.count == 16)
    #expect(MarshalSectors.starts(forCircuit: "Interlagos Grand Prix") == nil)
}
