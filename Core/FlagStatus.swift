import Foundation

/// A condition that applies to the whole circuit.
public enum TrackFlag: String, Sendable, Equatable {
    case clear, red, safetyCar, virtualSafetyCar

    public var label: String {
        switch self {
        case .clear: "Track clear"
        case .red: "Red flag"
        case .safetyCar: "Safety car"
        case .virtualSafetyCar: "Virtual safety car"
        }
    }

    /// The race-control flag this condition is shown as, for colour and symbol.
    public var kind: RaceControlKind {
        switch self {
        case .clear: .clear
        case .red: .red
        case .safetyCar: .safetyCar
        case .virtualSafetyCar: .virtualSafetyCar
        }
    }
}

public enum SectorFlagKind: String, Sendable, Equatable {
    case yellow, doubleYellow

    public var label: String { self == .yellow ? "Yellow flag" : "Double yellow" }
    public var kind: RaceControlKind { self == .yellow ? .yellow : .doubleYellow }
}

/// A yellow or double yellow in one numbered marshal sector.
public struct SectorFlag: Sendable, Equatable, Identifiable {
    public var id: Int { sector }
    public let sector: Int
    public let flag: SectorFlagKind
    public let since: String

    public init(sector: Int, flag: SectorFlagKind, since: String = "") {
        self.sector = sector
        self.flag = flag
        self.since = since
    }
}

/// One line of "what is flagged": a track-wide condition, or the sectors sharing one kind of yellow.
public struct FlagLine: Sendable, Equatable {
    public let kind: RaceControlKind
    public let text: String
}

/// What is flagged on the circuit right now, as the backend works it out from race control.
/// Decoding is forgiving: a flag the app does not know yet is left out instead of failing the snapshot.
public struct FlagStatus: Sendable, Equatable {
    public let track: TrackFlag
    public let trackSince: String?
    /// Lowest sector number first.
    public let sectors: [SectorFlag]

    public static let clear = FlagStatus()

    public init(track: TrackFlag = .clear, trackSince: String? = nil, sectors: [SectorFlag] = []) {
        self.track = track
        self.trackSince = trackSince
        self.sectors = sectors.sorted { $0.sector < $1.sector }
    }

    public var isClear: Bool { track == .clear && sectors.isEmpty }

    /// The kind of flag for one sector, if it is under yellow.
    public func flag(inSector sector: Int) -> SectorFlagKind? {
        sectors.first { $0.sector == sector }?.flag
    }

    /// Most urgent first: the whole track, then double yellows, then yellows. Empty when nothing is flagged.
    public var lines: [FlagLine] {
        var result: [FlagLine] = []
        if track != .clear { result.append(FlagLine(kind: track.kind, text: track.label)) }
        for kind in [SectorFlagKind.doubleYellow, .yellow] {
            let numbers = sectors.filter { $0.flag == kind }.map(\.sector)
            guard !numbers.isEmpty else { continue }
            let noun = numbers.count == 1 ? "sector" : "sectors"
            let list = numbers.map(String.init).joined(separator: ", ")
            result.append(FlagLine(kind: kind.kind, text: "\(kind == .yellow ? "Yellow" : "Double yellow") · \(noun) \(list)"))
        }
        return result
    }

    /// One sentence for VoiceOver, e.g. "Safety car. Double yellow in sectors 12 and 13."
    public var spokenDescription: String {
        lines.map { line in
            line.text.replacingOccurrences(of: " · ", with: " in ")
        }.joined(separator: ". ") + (lines.isEmpty ? "" : ".")
    }
}

extension FlagStatus: Codable {
    private enum CodingKeys: String, CodingKey { case track, trackSince, sectors }

    private struct Entry: Decodable {
        let sector: Int
        let flag: String
        let since: String?
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let track = (try? values.decodeIfPresent(String.self, forKey: .track)).flatMap { $0 }.flatMap(TrackFlag.init(rawValue:))
        let entries = (try? values.decodeIfPresent([LossyEntry].self, forKey: .sectors)) ?? []
        self.init(
            track: track ?? .clear,
            trackSince: (try? values.decodeIfPresent(String.self, forKey: .trackSince)).flatMap { $0 },
            sectors: entries.compactMap { entry in
                guard let entry = entry.value, entry.sector > 0, let kind = SectorFlagKind(rawValue: entry.flag) else { return nil }
                return SectorFlag(sector: entry.sector, flag: kind, since: entry.since ?? "")
            })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(track.rawValue, forKey: .track)
        try container.encode(trackSince, forKey: .trackSince)
        try container.encode(sectors.map { Wire(sector: $0.sector, flag: $0.flag.rawValue, since: $0.since) }, forKey: .sectors)
    }

    private struct Wire: Encodable { let sector: Int; let flag: String; let since: String }

    /// Decodes one array element, or nil when it is malformed, so one bad entry does not drop the others.
    private struct LossyEntry: Decodable {
        let value: Entry?
        init(from decoder: Decoder) throws { value = try? Entry(from: decoder) }
    }
}
