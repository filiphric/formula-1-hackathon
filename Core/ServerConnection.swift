import Foundation

public struct ServerConnection: Sendable {
    public private(set) var activeEndpoint: String
    public var draftEndpoint: String

    public init(endpoint: String) {
        activeEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        draftEndpoint = activeEndpoint
    }

    public mutating func beginEditing() {
        draftEndpoint = activeEndpoint
    }

    public mutating func connect() {
        activeEndpoint = draftEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
