import Foundation
import Testing
@testable import FormulaCore

// The calendar draws a small outline of each circuit. Names are the circuit names the race calendar
// (Jolpica) reports, seasons 2023 to 2026.

private let calendarCircuitsWithOutlines = [
    "Albert Park Grand Prix Circuit", "Circuit of the Americas", "Bahrain International Circuit", "Baku City Circuit",
    "Circuit de Barcelona-Catalunya", "Hungaroring", "Autodromo Enzo e Dino Ferrari", "Autódromo José Carlos Pace",
    "Jeddah Corniche Circuit", "Lusail International Circuit", "Marina Bay Street Circuit", "Miami International Autodrome",
    "Circuit de Monaco", "Autodromo Nazionale di Monza", "Red Bull Ring", "Autódromo Hermanos Rodríguez",
    "Shanghai International Circuit", "Silverstone Circuit", "Circuit de Spa-Francorchamps", "Suzuka Circuit",
    "Las Vegas Strip Street Circuit", "Circuit Gilles Villeneuve", "Yas Marina Circuit", "Circuit Park Zandvoort",
]

@Test func everyCalendarCircuitWithAnOutlineFindsItAndOthersGetNone() {
    for name in calendarCircuitsWithOutlines { #expect(CircuitShape.forCircuit(name) != nil, "\(name)") }
    // Venues with no published outline, names we do not know, and a missing name all get none, not a wrong shape.
    #expect(CircuitShape.forCircuit("Madring") == nil)
    #expect(CircuitShape.forCircuit("Sepang International Circuit") == nil)
    #expect(CircuitShape.forCircuit("Sample circuit") == nil)
    #expect(CircuitShape.forCircuit(nil) == nil)
    #expect(CircuitShape.forCircuit("  Hungaroring ") != nil)
}

@Test func everyOutlineIsAUsableClosedLoopInsideItsBox() throws {
    for name in calendarCircuitsWithOutlines {
        let shape = try #require(CircuitShape.forCircuit(name), "\(name)")
        #expect(shape.points.count >= 20, "\(name) has too few points to look like a circuit")
        #expect(shape.points.allSatisfy { (0...1000).contains($0.x) && (0...1000).contains($0.y) }, "\(name)")
        // The longer side fills the box, so every circuit is drawn at the same scale.
        #expect(abs(max(shape.width, shape.height) - 1000) < 1, "\(name)")
        #expect(shape.width > 100 && shape.height > 100, "\(name)")
        #expect(shape.aspectRatio == shape.width / shape.height)
    }
}

@Test func circuitsAreNotAllTheSameShape() throws {
    let monza = try #require(CircuitShape.forCircuit("Autodromo Nazionale di Monza"))
    let monaco = try #require(CircuitShape.forCircuit("Circuit de Monaco"))
    #expect(monza.points != monaco.points)
    // Monza is the long flat one; Monaco is cramped. Compare their drawn proportions.
    #expect(monza.aspectRatio != monaco.aspectRatio)
}

@Test func interlagosOutlineFacesTheSameWayAsTheLiveMap() throws {
    let url = try #require(Bundle.module.url(forResource: "interlagos-track", withExtension: "json", subdirectory: "Fixtures"))
    let live = try JSONDecoder().decode(TrackLayout.self, from: Data(contentsOf: url))
    let rotation = CircuitOrientation.rotation(forCircuit: "Interlagos")
    let shape = try #require(CircuitShape.forCircuit("Autódromo José Carlos Pace"))

    // The OpenF1 live trace, turned by its rotation, and the calendar outline are two sources for one circuit.
    #expect(abs(try #require(live.aspectRatio(rotationDegrees: rotation)) - shape.aspectRatio) < 0.06)
    #expect(shape.aspectRatio > 1.3)

    let projection = try #require(live.projection(width: 1064, height: 1064, rotationDegrees: rotation))
    let drawn = live.points.compactMap { projection.project(x: $0.x, y: $0.y) }
    func unit(_ point: TrackPoint, in cloud: [TrackPoint]) -> (x: Double, y: Double) {
        let xs = cloud.map(\.x), ys = cloud.map(\.y)
        return ((point.x - xs.min()!) / (xs.max()! - xs.min()!), (point.y - ys.min()!) / (ys.max()! - ys.min()!))
    }
    // The start/finish line sits in the same place of the circuit: along the top, left of centre.
    let liveStart = unit(drawn[0], in: drawn), shapeStart = unit(shape.points[0], in: shape.points)
    #expect(abs(liveStart.x - shapeStart.x) < 0.06 && abs(liveStart.y - shapeStart.y) < 0.06)
    #expect(shapeStart.y < 0.1)
}

@Test func aWeekendFindsItsCircuitOutlineByCircuitName() throws {
    func weekend(_ circuit: String) throws -> RaceWeekend {
        try JSONDecoder().decode(RaceWeekend.self, from: Data(#"{"round":1,"name":"GP","circuit":"\#(circuit)","country":"X","sessions":[]}"#.utf8))
    }
    #expect(try weekend("Suzuka Circuit").circuitShape == CircuitShape.forCircuit("Suzuka Circuit"))
    #expect(try weekend("Suzuka Circuit").circuitShape != nil)
    #expect(try weekend("Sample circuit").circuitShape == nil)
}
