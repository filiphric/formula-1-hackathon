import Foundation
import Testing
@testable import FormulaCore

private func trackSnapshot(mode: String = "live", upstream: String = "connected", date: String = "2026-11-06T12:00:05.250Z") throws -> TimingSnapshot {
    let payload: [String: Any] = [
        "mode": mode, "upstream": upstream,
        "session": ["name": "Qualifying", "circuit": "Test circuit", "start": "2026-11-06T12:00:00Z", "end": "2026-11-06T13:00:00Z"],
        "track": ["source": "OpenF1", "points": [["x": -100, "y": -50], ["x": 100, "y": 50]]],
        "drivers": [["number": 4, "name": "Norris", "acronym": "NOR", "team": "McLaren", "color": "FF8000",
                     "location": ["x": 0, "y": 50, "date": date]]], "messages": []
    ]
    return try TimingSnapshot.decode(JSONSerialization.data(withJSONObject: payload))
}

@Test func decodesTrackAndFractionalDriverCoordinates() throws {
    let snapshot = try trackSnapshot()
    #expect(snapshot.track?.points.count == 2)
    #expect(snapshot.drivers[0].location?.y == 50)
    #expect(snapshot.drivers[0].location?.timestamp == TrackLayout.parseDate("2026-11-06T12:00:05.250Z"))
    let legacy = try TimingSnapshot.decode(Data(#"{"mode":"live","upstream":"connected","drivers":[],"messages":[]}"#.utf8))
    #expect(legacy.track == nil)
}

@Test func projectsTrackAndDriverTogetherWithAspectRatioAndInvertedY() throws {
    let track = try #require(try trackSnapshot().track)
    let projection = try #require(track.projection(width: 400, height: 300))
    let topLeft = try #require(projection.project(x: -100, y: 50))
    let bottomRight = try #require(projection.project(x: 100, y: -50))
    let driver = try #require(projection.project(x: 0, y: 50))
    #expect(abs(topLeft.x - 32) < 0.001)
    #expect(abs(topLeft.y - 66) < 0.001)
    #expect(abs(bottomRight.x - 368) < 0.001)
    #expect(abs(bottomRight.y - 234) < 0.001)
    #expect(abs(driver.x - 200) < 0.001)
    #expect(driver.y == topLeft.y)
    #expect(projection.project(x: .nan, y: 0) == nil)
    #expect(track.projection(width: 10, height: 10) == nil)
    let invalid = try JSONDecoder().decode(TrackLayout.self, from: Data(#"{"source":"test","points":[{"x":1,"y":1},{"x":1,"y":1}]}"#.utf8))
    #expect(invalid.projection(width: 400, height: 300) == nil)
}

@Test func marksEachLocationStaleIndependentlyOfTimingFeed() throws {
    let location = try #require(try trackSnapshot().drivers[0].location)
    #expect(!location.isStale(at: try #require(TrackLayout.parseDate("2026-11-06T12:00:15.250Z"))))
    #expect(location.isStale(at: try #require(TrackLayout.parseDate("2026-11-06T12:00:16Z"))))
    #expect(location.isStale(at: try #require(TrackLayout.parseDate("2026-11-06T11:00:00Z"))))
}

@Test func distinguishesLiveHistoricalDemoDisconnectedAndMissingCoordinates() throws {
    let now = try #require(TrackLayout.parseDate("2026-11-06T12:00:10Z"))
    #expect(try trackSnapshot().trackStatus(at: now, connected: true) == "LIVE · Driver locations")
    #expect(try trackSnapshot(mode: "demo").trackStatus(at: now, connected: true) == "DEMO · Simulated positions")
    #expect(try trackSnapshot().trackStatus(at: now, connected: false) == "Disconnected · Last known positions")
    #expect(try trackSnapshot(upstream: "reconnecting").trackStatus(at: now, connected: true) == "Disconnected · Last known positions")
    let missing = try TimingSnapshot.decode(Data(#"{"mode":"live","upstream":"connected","session":{"name":"Practice","circuit":"Test","start":"2026-11-06T12:00:00Z","end":"2026-11-06T13:00:00Z"},"drivers":[],"messages":[]}"#.utf8))
    #expect(missing.trackStatus(at: now, connected: true) == "Waiting for driver locations")
    let later = try #require(TrackLayout.parseDate("2026-11-06T14:00:00Z"))
    #expect(try trackSnapshot().trackStatus(at: later, connected: true) == "Session ended · Last known positions")
    let stale = try #require(TrackLayout.parseDate("2026-11-06T12:00:20Z"))
    #expect(try trackSnapshot().trackStatus(at: stale, connected: true) == "Stale · No recent driver locations")
}
