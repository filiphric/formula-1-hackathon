import Foundation

public struct TimingSnapshot: Codable, Sendable {
    public let mode: String
    public let upstream: String
    public let updatedAt: String?
    public let session: RaceSession?
    public let drivers: [TimingDriver]
    public let messages: [RaceMessage]

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

    public var formattedLap: String {
        guard let lapTime, lapTime.isFinite, lapTime > 0 else { return "—" }
        let milliseconds = Int((lapTime * 1000).rounded())
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
