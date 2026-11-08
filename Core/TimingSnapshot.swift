import Foundation

public struct TimingSnapshot: Codable, Sendable {
    public let mode: String
    public let upstream: String
    public let updatedAt: String?
    public let session: RaceSession?
    public let drivers: [TimingDriver]
    public let messages: [RaceMessage]
    public let track: TrackLayout?
    /// Newest first. Absent from servers that predate team radio.
    public let radios: [TeamRadio]
    /// Which sectors are under yellow and whether the whole track is red or under a safety car.
    /// Absent from servers that predate flag tracking, which reads as nothing flagged.
    public let flags: FlagStatus

    public init(mode: String, upstream: String, updatedAt: String?, session: RaceSession?,
                drivers: [TimingDriver], messages: [RaceMessage], track: TrackLayout?, radios: [TeamRadio] = [],
                flags: FlagStatus = .clear) {
        self.mode = mode
        self.upstream = upstream
        self.updatedAt = updatedAt
        self.session = session
        self.drivers = drivers
        self.messages = messages
        self.track = track
        self.radios = radios
        self.flags = flags
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = try values.decode(String.self, forKey: .mode)
        upstream = try values.decode(String.self, forKey: .upstream)
        updatedAt = try values.decodeIfPresent(String.self, forKey: .updatedAt)
        session = try values.decodeIfPresent(RaceSession.self, forKey: .session)
        drivers = try values.decode([TimingDriver].self, forKey: .drivers)
        messages = try values.decode([RaceMessage].self, forKey: .messages)
        track = try values.decodeIfPresent(TrackLayout.self, forKey: .track)
        radios = try values.decodeIfPresent([TeamRadio].self, forKey: .radios) ?? []
        flags = (try? values.decodeIfPresent(FlagStatus.self, forKey: .flags)).flatMap { $0 } ?? .clear
    }

    public static func decode(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }
}

public struct RaceSession: Codable, Sendable {
    public let name: String
    public let circuit: String
    public let start: String
    public let end: String
}

public struct TimingDriver: Codable, Identifiable, Sendable {
    public var id: Int { number }
    public let number: Int
    public let name: String
    public let acronym: String
    public let team: String
    public let color: String
    public let position: Int?
    public let gap: String?
    public let lap: Int?
    public let lapTime: Double?
    public let compound: String?
    public let location: DriverLocation?
    /// Gap to the car directly ahead. Absent from older backends, and for the leader.
    public var interval: String? = nil
    /// The driver's fastest completed lap of the session, in seconds. Absent from older backends.
    public var bestLap: Double? = nil
    /// The car is in the pit lane right now. Absent from older backends, which reads as on track.
    public var inPit: Bool? = nil

    public var isInPit: Bool { inPit == true }

    public var formattedLap: String { Self.format(lap: lapTime) }
    public var formattedBestLap: String { Self.format(lap: bestLap) }

    private static func format(lap seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "—" }
        let milliseconds = Int((seconds * 1000).rounded())
        return String(format: "%d:%02d.%03d", milliseconds / 60000,
                      (milliseconds / 1000) % 60, milliseconds % 1000)
    }
}

public struct RaceMessage: Codable, Identifiable, Sendable {
    public let id: String
    public let date: String
    public let message: String
    public let flag: String?
}

public struct TrackPoint: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct DriverLocation: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let date: String

    public let timestamp: Date?

    private enum CodingKeys: String, CodingKey { case x, y, date }

    public init(x: Double, y: Double, date: String) {
        self.x = x
        self.y = y
        self.date = date
        timestamp = TrackLayout.parseDate(date)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(x: try values.decode(Double.self, forKey: .x),
                  y: try values.decode(Double.self, forKey: .y),
                  date: try values.decode(String.self, forKey: .date))
    }

    public func isStale(at now: Date) -> Bool {
        guard let timestamp else { return true }
        return now.timeIntervalSince(timestamp) > 10 || timestamp.timeIntervalSince(now) > 5
    }
}

public struct TrackLayout: Codable, Sendable, Equatable {
    public let source: String
    public let points: [TrackPoint]
    /// MultiViewer/FastF1 rotation, counterclockwise in telemetry coordinates.
    public var rotationDegrees: Double? = nil

    public var orientedPoints: [TrackPoint] { points.map { rotate($0) } }

    private func rotate(_ point: TrackPoint) -> TrackPoint {
        TrackProjection.rotate(point, degrees: rotationDegrees ?? 0)
    }

    /// Building an `ISO8601DateFormatter` is expensive and views parse timestamps many times per
    /// render, so the two formatters are created once. `Formatter` is thread-safe for parsing.
    private nonisolated(unsafe) static let fractionalParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private nonisolated(unsafe) static let plainParser = ISO8601DateFormatter()

    public static func parseDate(_ value: String) -> Date? {
        fractionalParser.date(from: value) ?? plainParser.date(from: value)
    }

    public func projection(width: Double, height: Double) -> TrackProjection? {
        TrackProjection(points: points, width: width, height: height, rotationDegrees: rotationDegrees ?? 0)
    }
}

public struct TrackProjection: Sendable {
    private let rotationDegrees: Double
    private let minX: Double
    private let maxY: Double
    private let scale: Double
    private let offsetX: Double
    private let offsetY: Double

    public init?(points: [TrackPoint], width: Double, height: Double, rotationDegrees: Double = 0) {
        guard rotationDegrees.isFinite else { return nil }
        self.rotationDegrees = rotationDegrees
        let points = points.map { Self.rotate($0, degrees: rotationDegrees) }
        guard points.count >= 2, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              width.isFinite, height.isFinite, width > 64, height > 64,
              let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(),
              maxX > minX, maxY > minY else { return nil }
        self.minX = minX
        self.maxY = maxY
        scale = min((width - 64) / (maxX - minX), (height - 64) / (maxY - minY))
        offsetX = (width - (maxX - minX) * scale) / 2
        offsetY = (height - (maxY - minY) * scale) / 2
    }

    public static func rotate(_ point: TrackPoint, degrees: Double) -> TrackPoint {
        let radians = degrees * .pi / 180
        return TrackPoint(x: point.x * cos(radians) - point.y * sin(radians),
                          y: point.x * sin(radians) + point.y * cos(radians))
    }

    public func project(x: Double, y: Double) -> TrackPoint? {
        guard x.isFinite, y.isFinite else { return nil }
        let point = Self.rotate(TrackPoint(x: x, y: y), degrees: rotationDegrees)
        return TrackPoint(x: offsetX + (point.x - minX) * scale, y: offsetY + (maxY - point.y) * scale)
    }
}

extension TimingSnapshot {
    /// The flags worth showing now. Once a real session is past its scheduled end and no car is reporting a
    /// position, whatever yellow or safety car was last flagged is history, so nothing is shown. A red flag
    /// is the exception: it is what extends a session past its schedule, and cars at rest may report nothing.
    /// Demo flags are always shown.
    public func activeFlags(at now: Date) -> FlagStatus {
        if mode == "demo" || flags.track == .red { return flags }
        if let end = session.flatMap({ TrackLayout.parseDate($0.end) }), now > end,
           !drivers.compactMap(\.location).contains(where: { !$0.isStale(at: now) }) {
            return .clear
        }
        return flags
    }

    public func trackStatus(at now: Date, connected: Bool) -> String {
        if mode == "demo" { return "DEMO · Simulated positions" }
        guard connected, upstream == "connected" else { return "Disconnected · Last known positions" }
        guard let session, let start = TrackLayout.parseDate(session.start),
              let end = TrackLayout.parseDate(session.end) else { return "Session time unavailable" }
        let locations = drivers.compactMap(\.location)
        if now > end && !locations.contains(where: { !$0.isStale(at: now) }) {
            return "Session ended · Last known positions"
        }
        if now < start { return "Session has not started" }
        if locations.isEmpty { return "Waiting for driver locations" }
        if locations.allSatisfy({ $0.isStale(at: now) }) { return "Stale · No recent driver locations" }
        return "LIVE · Driver locations"
    }
}

/// Presentation semantics for the standard tyre markings; unknown data must not
/// masquerade as a known compound just because its first letter matches.
public enum TyreCompound: Sendable {
    case soft, medium, hard, intermediate, wet, unknown

    public init(_ value: String?) {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "SOFT": self = .soft
        case "MEDIUM": self = .medium
        case "HARD": self = .hard
        case "INTERMEDIATE": self = .intermediate
        case "WET": self = .wet
        default: self = .unknown
        }
    }

    public var symbol: String {
        switch self {
        case .soft: "S"
        case .medium: "M"
        case .hard: "H"
        case .intermediate: "I"
        case .wet: "W"
        case .unknown: "?"
        }
    }

    public var label: String {
        switch self {
        case .soft: "Soft tyre"
        case .medium: "Medium tyre"
        case .hard: "Hard tyre"
        case .intermediate: "Intermediate tyre"
        case .wet: "Wet tyre"
        case .unknown: "Tyre unknown"
        }
    }
}
