import Foundation

public struct ServerConnection: Sendable {
    public private(set) var activeEndpoint: String
    public var draftEndpoint: String

    public init(endpoint: String) {
        activeEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        draftEndpoint = activeEndpoint
    }

    /// The live-timing URL for an address, or nil when it is not a plain `ws://` or `wss://` address.
    public static func timingURL(from endpoint: String) -> URL? {
        guard let url = URL(string: endpoint),
              ["ws", "wss"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }

    public mutating func beginEditing() {
        draftEndpoint = activeEndpoint
    }

    public mutating func connect() {
        activeEndpoint = draftEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
