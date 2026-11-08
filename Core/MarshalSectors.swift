import Foundation

/// Where each numbered marshal sector lies on the circuit outline, so a flagged sector can be drawn.
///
/// Race control names a sector by number only. Each circuit's table gives where sector N starts; a
/// sector then runs along the track from its start to the next sector's start, and the last sector
/// runs on across the start line to sector 1.
public struct SectorRuns: Sendable, Equatable {
    /// Number of marshal sectors on the circuit.
    public let count: Int
    /// Sector number (from 1) -> its stretch of the outline. A sector that crosses the point where the
    /// recorded lap begins comes back as two pieces.
    public let runs: [Int: [[TrackPoint]]]

    public func points(forSector sector: Int) -> [[TrackPoint]] { runs[sector] ?? [] }
}

public enum MarshalSectors {
    /// A start further than this fraction of the outline's size from the outline is not on this track
    /// (a different layout or coordinate frame), so the table is not used.
    static let maxOffTrackFraction = 0.04

    /// The start of each marshal sector for a circuit named as the live session names it (sector 1 first).
    public static func starts(forCircuit circuit: String?) -> [TrackPoint]? {
        guard let name = circuit?.trimmingCharacters(in: .whitespacesAndNewlines),
              let encoded = MarshalSectorData.starts[name] else { return nil }
        let points = encoded.split(separator: " ").compactMap { pair -> TrackPoint? in
            let parts = pair.split(separator: ",")
            guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
            return TrackPoint(x: x, y: y)
        }
        return points.count >= 3 ? points : nil
    }

    /// Place the sectors on `outline`. Returns nil when the starts do not fit it: any start far from the
    /// outline, or starts that do not run once around it in order. Showing no sector then is better
    /// than shading the wrong stretch of track.
    public static func runs(starts: [TrackPoint], along outline: [TrackPoint]) -> SectorRuns? {
        guard starts.count >= 3, outline.count >= 2,
              let path = Path2D(outline) else { return nil }
        let size = path.size
        var arcs: [Double] = []
        for start in starts {
            guard start.x.isFinite, start.y.isFinite else { return nil }
            let (arc, distance) = path.nearest(to: start)
            guard distance <= size * maxOffTrackFraction else { return nil }
            arcs.append(arc)
        }
        return build(arcs: arcs, on: path)
    }

    /// Split the outline into `count` sectors of equal length, for the demo circuit that has no real sectors.
    public static func evenRuns(count: Int, along outline: [TrackPoint]) -> SectorRuns? {
        guard count >= 3, outline.count >= 2, let path = Path2D(outline) else { return nil }
        return build(arcs: (0..<count).map { path.length * Double($0) / Double(count) }, on: path)
    }

    /// `arcs[i]` is how far along the outline sector i+1 starts. They must increase once around the lap.
    private static func build(arcs: [Double], on path: Path2D) -> SectorRuns? {
        let count = arcs.count
        // One wrap past the end of the recorded lap is expected; every other step must move forward.
        var wraps = 0
        for index in 0..<count {
            let next = arcs[(index + 1) % count]
            if next < arcs[index] { wraps += 1 } else if next == arcs[index] { return nil }
        }
        guard wraps <= 1 else { return nil }
        var runs: [Int: [[TrackPoint]]] = [:]
        for index in 0..<count {
            let from = arcs[index], to = arcs[(index + 1) % count]
            if from < to {
                runs[index + 1] = [path.slice(from: from, to: to)]
            } else {
                // Crossing the recorded start: the end of the outline, then its beginning. A piece with no length is left out.
                var pieces: [[TrackPoint]] = []
                if from < path.length { pieces.append(path.slice(from: from, to: path.length)) }
                if to > 0 { pieces.append(path.slice(from: 0, to: to)) }
                runs[index + 1] = pieces                }
        }
        return SectorRuns(count: count, runs: runs)
    }
}

/// An open polyline measured by distance along it.
private struct Path2D {
    let points: [TrackPoint]
    /// Distance from the first point to each point.
    let cumulative: [Double]
    var length: Double { cumulative.last ?? 0 }
    /// Diagonal of the bounding box.
    let size: Double

    init?(_ points: [TrackPoint]) {
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        var total = 0.0
        var cumulative = [0.0]
        for (a, b) in zip(points, points.dropFirst()) {
            total += hypot(b.x - a.x, b.y - a.y)
            cumulative.append(total)
        }
        guard total > 0, let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        self.points = points
        self.cumulative = cumulative
        size = hypot(maxX - minX, maxY - minY)
    }

    /// Distance along the path of the point closest to `target`, and how far `target` is from the path.
    func nearest(to target: TrackPoint) -> (arc: Double, distance: Double) {
        var best = (arc: 0.0, distance: Double.infinity)
        for index in 0..<(points.count - 1) {
            let a = points[index], b = points[index + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let span = dx * dx + dy * dy
            let t = span == 0 ? 0 : min(max(((target.x - a.x) * dx + (target.y - a.y) * dy) / span, 0), 1)
            let distance = hypot(target.x - (a.x + t * dx), target.y - (a.y + t * dy))
            if distance < best.distance {
                best = (cumulative[index] + t * (cumulative[index + 1] - cumulative[index]), distance)
            }
        }
        return best
    }

    func point(at arc: Double) -> TrackPoint {
        let clamped = min(max(arc, 0), length)
        var index = 0
        while index < points.count - 2, cumulative[index + 1] < clamped { index += 1 }
        let a = points[index], b = points[index + 1]
        let span = cumulative[index + 1] - cumulative[index]
        let t = span == 0 ? 0 : (clamped - cumulative[index]) / span
        return TrackPoint(x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y))
    }

    /// The stretch between two distances: both ends, and every vertex between them.
    func slice(from: Double, to: Double) -> [TrackPoint] {
        var result = [point(at: from)]
        for (index, distance) in cumulative.enumerated() where distance > from && distance < to {
            result.append(points[index])
        }
        result.append(point(at: to))
        return result
    }
}

extension TrackLayout {
    /// Where the marshal sectors lie on this outline, for the circuit the session is at. Demo timing uses
    /// twelve equal parts of its fictional circuit. Nil when the circuit's sectors are not known or do
    /// not fit this outline.
    public func sectorRuns(circuit: String?, isDemo: Bool) -> SectorRuns? {
        if isDemo { return MarshalSectors.evenRuns(count: 12, along: points) }
        guard let starts = MarshalSectors.starts(forCircuit: circuit) else { return nil }
        return MarshalSectors.runs(starts: starts, along: points)
    }
}
