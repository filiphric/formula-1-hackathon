import Foundation

/// One driver radio clip as the backend reports it. `recordingUrl` is nil for demo clips, which have no audio.
public struct TeamRadio: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let date: String
    public let driverNumber: Int
    public let recordingUrl: String?

    public init(id: String, date: String, driverNumber: Int, recordingUrl: String?) {
        self.id = id
        self.date = date
        self.driverNumber = driverNumber
        self.recordingUrl = recordingUrl
    }

    public var timestamp: Date? { TrackLayout.parseDate(date) }

    /// Only a plain https link with a host is ever played, whatever the server sent.
    public var playbackURL: URL? {
        guard let recordingUrl, let url = URL(string: recordingUrl),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}

extension TimingSnapshot {
    public func driver(for radio: TeamRadio) -> TimingDriver? {
        drivers.first { $0.number == radio.driverNumber }
    }

    /// Says whether the clips are sample, live or last-known, the same way the track page does.
    public func radioStatus(connected: Bool, now: Date) -> String {
        if mode == "demo" { return "DEMO · Sample clips, no audio" }
        guard connected, upstream == "connected" else { return "Disconnected · Last known clips" }
        if let end = session.flatMap({ TrackLayout.parseDate($0.end) }), now > end {
            return radios.isEmpty ? "Session ended · No team radio" : "Session ended · All clips from this session"
        }
        return radios.isEmpty ? "Waiting for team radio" : "LIVE · Latest team radio"
    }
}

extension TeamRadio {
    /// What VoiceOver reads for the row: who is talking, when, and whether it can be played.
    public func accessibilitySummary(driver: TimingDriver?, timeText: String?) -> String {
        let who = driver.map { "\($0.name), \($0.team)" } ?? "Driver \(driverNumber)"
        var parts = ["Team radio", who]
        if let timeText, !timeText.isEmpty { parts.append(timeText) }
        if playbackURL == nil { parts.append("No audio available") }
        return parts.joined(separator: ", ")
    }

    /// Bar heights (0.25...1) for the clip's waveform strip. They come from the clip id so a row never
    /// changes shape between refreshes; they are decoration, not the recording's real loudness.
    public static func waveform(seed: String, bars: Int) -> [Double] {
        var state: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 { state = (state ^ UInt64(byte)) &* 1_099_511_628_211 }
        return (0..<max(bars, 0)).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return 0.25 + 0.75 * Double(state >> 40) / Double(1 << 24)
        }
    }
}
