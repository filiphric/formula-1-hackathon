import Foundation

/// A small outline of a circuit for the calendar: the lap as a closed loop, turned to the way the official
/// track map faces, in a box whose longer side is 1000 and whose y axis points down (screen coordinates).
public struct CircuitShape: Sendable, Equatable {
    public let points: [TrackPoint]
    public let width: Double
    public let height: Double

    /// Width over height, so a view can give the outline its own proportions.
    public var aspectRatio: Double { width / height }

    /// The outline for a circuit named as the race calendar names it, or nil when none is published.
    public static func forCircuit(_ name: String?) -> CircuitShape? {
        name.flatMap { all[$0.trimmingCharacters(in: .whitespacesAndNewlines)] }
    }

    private static let all: [String: CircuitShape] = CircuitShapeData.outlines.compactMapValues(parse)

    private static func parse(_ encoded: String) -> CircuitShape? {
        let points = encoded.split(separator: " ").compactMap { pair -> TrackPoint? in
            let parts = pair.split(separator: ",")
            guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
            return TrackPoint(x: x, y: y)
        }
        guard points.count >= 3,
              let maxX = points.map(\.x).max(), let maxY = points.map(\.y).max(), maxX > 0, maxY > 0 else { return nil }
        return CircuitShape(points: points, width: maxX, height: maxY)
    }
}

extension RaceWeekend {
    /// The circuit's outline for the calendar, when there is one.
    public var circuitShape: CircuitShape? { CircuitShape.forCircuit(circuit) }
}
