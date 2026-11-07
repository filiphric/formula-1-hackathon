import Foundation
import Testing
@testable import FormulaCore

// Map under test: a 1000 x 500 circuit in a 464 x 264 view. With 32 points of margin each side the
// scale is 400 / 1000 = 0.4 and the circuit is inset 32 points, so screen x = 32 + 0.4 * x.
// Telemetry y grows upward, so a larger y sits higher on screen (smaller screen y).
private let epoch = TrackLayout.parseDate("2026-11-07T12:00:00Z")!

private func projection() throws -> TrackProjection {
    let track = TrackLayout(source: "test", points: [TrackPoint(x: 0, y: 0), TrackPoint(x: 1000, y: 500)])
    return try #require(track.projection(width: 464, height: 264))
}

private func drivers(_ entries: [(number: Int, x: Double, y: Double, second: Int)?]) throws -> [TimingDriver] {
    let numbers = [4, 16, 1]
    let payload: [String: Any] = [
        "mode": "live", "upstream": "connected", "messages": [],
        "drivers": entries.enumerated().map { index, entry -> [String: Any] in
            var driver: [String: Any] = ["number": numbers[index], "name": "Driver \(index)", "acronym": "D\(index)",
                                         "team": "Team", "color": "FF8000"]
            if let entry {
                driver["location"] = ["x": entry.x, "y": entry.y,
                                      "date": "2026-11-07T12:00:\(String(format: "%02d", entry.second))Z"]
            }
            return driver
        }
    ]
    return try TimingSnapshot.decode(JSONSerialization.data(withJSONObject: payload)).drivers
}

private func spots(_ list: [TimingDriver], _ motions: [Int: DriverMotion], at seconds: Double,
                   connected: Bool = true, animated: Bool = true) throws -> [Int: TrackPoint] {
    MarkerLayout.spots(drivers: list, motions: motions, projection: try projection(),
                       now: epoch.addingTimeInterval(seconds), connected: connected, animated: animated,
                       markerSize: 28, width: 464, height: 264)
}

/// Car 4 reported x=0, then x=1000 a second later (arriving at t=1s).
private func easedCar() throws -> (drivers: [TimingDriver], motions: [Int: DriverMotion]) {
    var motion = DriverMotion()
    motion.receive(DriverLocation(x: 0, y: 250, date: "2026-11-07T12:00:00Z"), at: epoch)
    motion.receive(DriverLocation(x: 1000, y: 250, date: "2026-11-07T12:00:01Z"), at: epoch.addingTimeInterval(1))
    return (try drivers([(4, 1000, 250, 1)]), [4: motion])
}

@Test func markerHalfwayThroughAOneSecondUpdateIsHalfwayOnScreen() throws {
    let (list, motions) = try easedCar()
    // x = 0 -> 32, x = 500 -> 232, x = 1000 -> 432.
    #expect(try spots(list, motions, at: 1)[4]?.x == 32)
    #expect(try spots(list, motions, at: 1.5)[4]?.x == 232)
    #expect(try spots(list, motions, at: 2)[4]?.x == 432)
    // Telemetry y = 250 is the vertical middle of the circuit: 32 + 0.4 * 250 = 132.
    #expect(try spots(list, motions, at: 1.5)[4]?.y == 132)
}

@Test func markerIsDrawnAtTheReceivedPositionWithoutEasingWhenDisconnectedOrReducedMotion() throws {
    let (list, motions) = try easedCar()
    #expect(try spots(list, motions, at: 1.5, connected: false)[4]?.x == 432)
    #expect(try spots(list, motions, at: 1.5, animated: false)[4]?.x == 432)
}

@Test func markerWithoutMotionYetOrWithStaleLocationUsesTheReceivedPosition() throws {
    let list = try drivers([(4, 500, 250, 1)])
    // No motion recorded yet (for example just after a reset): the received position is drawn.
    #expect(try spots(list, [:], at: 1.5)[4]?.x == 232)
    // Eleven seconds after the report the location is stale: one old spot, never eased.
    var motion = DriverMotion()
    motion.receive(DriverLocation(x: 0, y: 250, date: "2026-11-07T12:00:00Z"), at: epoch)
    motion.receive(DriverLocation(x: 500, y: 250, date: "2026-11-07T12:00:01Z"), at: epoch.addingTimeInterval(1))
    #expect(try spots(list, [4: motion], at: 12.5)[4]?.x == 232)
}

@Test func driversWithoutALocationAreNotPlotted() throws {
    let list = try drivers([(4, 0, 0, 1), nil, (1, 1000, 500, 1)])
    let result = try spots(list, [:], at: 1)
    #expect(Set(result.keys) == [4, 1])
}

@Test func overlappingMarkersAreSeparatedAndTheLowerCarNumberKeepsItsSpot() throws {
    let list = try drivers([(4, 500, 250, 1), (16, 500, 250, 1), (1, 500, 250, 1)])
    let result = try spots(list, [:], at: 1)
    // Car 1 is the lowest number, so it keeps the exact spot; 16 and 4 move at least 95% of a marker apart.
    #expect(result[1]?.x == 232)
    let placed = [1, 4, 16].compactMap { result[$0] }
    #expect(placed.count == 3)
    for (index, a) in placed.enumerated() {
        for b in placed.dropFirst(index + 1) { #expect(hypot(a.x - b.x, a.y - b.y) >= 28 * 0.95 - 1e-9) }
    }
}

@Test func tapSelectsTheNearestMarkerWithinTheTouchRadius() {
    let spots = [4: TrackPoint(x: 100, y: 100), 16: TrackPoint(x: 120, y: 100)]
    #expect(MarkerLayout.driver(at: TrackPoint(x: 104, y: 100), in: spots, radius: 14) == 4)
    #expect(MarkerLayout.driver(at: TrackPoint(x: 118, y: 103), in: spots, radius: 14) == 16)
    #expect(MarkerLayout.driver(at: TrackPoint(x: 110, y: 100), in: spots, radius: 14) == 4)
    #expect(MarkerLayout.driver(at: TrackPoint(x: 200, y: 200), in: spots, radius: 14) == nil)
    #expect(MarkerLayout.driver(at: TrackPoint(x: 100, y: 115), in: spots, radius: 14) == nil)
    #expect(MarkerLayout.driver(at: TrackPoint(x: 100, y: 100), in: [:], radius: 14) == nil)
}

@Test func tapBetweenTwoMarkersInsideTheTouchRadiusPicksTheNearerOne() {
    // 44-point touch target (radius 22): a tap 5 points from car 4 and 15 points from car 16 hits both
    // targets, and must choose car 4. Mirrored, the same tap chooses car 16.
    let spots = [4: TrackPoint(x: 100, y: 100), 16: TrackPoint(x: 120, y: 100)]
    #expect(MarkerLayout.driver(at: TrackPoint(x: 105, y: 100), in: spots, radius: 22) == 4)
    #expect(MarkerLayout.driver(at: TrackPoint(x: 115, y: 100), in: spots, radius: 22) == 16)
}

// Motion lasts at most one second after a position arrives. Per-frame drawing must cover all of it, and a
// timer that was started for an older position must not switch drawing off because a newer one has arrived.
@Test func frameDrawingCoversTheWholeEasingAndStopsSoonAfter() {
    let received = epoch
    #expect(MotionActivity.isActive(lastReceived: received, now: received))
    #expect(MotionActivity.isActive(lastReceived: received, now: received.addingTimeInterval(1)))
    // One-second feeds can be a few tens of milliseconds late: still no idle gap before the next position.
    #expect(MotionActivity.isActive(lastReceived: received, now: received.addingTimeInterval(1.1)))
    #expect(!MotionActivity.isActive(lastReceived: received, now: received.addingTimeInterval(1.5)))
    #expect(!MotionActivity.isActive(lastReceived: .distantPast, now: received))
}

@Test func anOlderTimerWakingJustAfterANewPositionDoesNotIdleTheMap() {
    // Position A arrived at t=0 and started a one-second-and-a-bit timer. Position B arrives at t=1.081 and
    // A's timer fires at t=1.082: the newest position is one millisecond old, so the map must keep animating.
    let newest = epoch.addingTimeInterval(1.081)
    #expect(MotionActivity.isActive(lastReceived: newest, now: epoch.addingTimeInterval(1.082)))
}

// A marker that closes in on another one smoothly must be drawn moving smoothly: stepping a true position
// by 0.25 point may move the drawn marker by at most 0.25 point, never snap it a whole marker away.
@Test func aMarkerApproachingAnotherSlidesApartInsteadOfJumping() {
    let minDistance = 28.0
    let fixed = TrackPoint(x: 100, y: 100)
    for angle in stride(from: 0.0, to: 2 * Double.pi, by: Double.pi / 6) {
        var previous: TrackPoint?
        var step = 0
        while true {
            let distance = 60 - 0.25 * Double(step)          // 60 point away, closing to 10 points
            if distance < 10 { break }
            let moving = TrackPoint(x: 100 + distance * cos(angle), y: 100 + distance * sin(angle))
            let drawn = MarkerSpread.separated([fixed, moving], minDistance: minDistance)
            #expect(drawn[0] == fixed)
            #expect(hypot(drawn[1].x - fixed.x, drawn[1].y - fixed.y) >= minDistance - 1e-9)
            if let previous {
                #expect(hypot(drawn[1].x - previous.x, drawn[1].y - previous.y) <= 0.25 + 1e-9,
                        "marker jumped at distance \(distance), angle \(angle)")
            }
            previous = drawn[1]
            step += 1
        }
    }
}
