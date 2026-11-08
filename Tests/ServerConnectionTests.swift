import Foundation
import Testing
@testable import FormulaCore

@Test func timingAddressMustBeAPlainWebSocketAddress() {
    #expect(ServerConnection.timingURL(from: "ws://localhost:8787/live")?.absoluteString == "ws://localhost:8787/live")
    #expect(ServerConnection.timingURL(from: "WSS://example.com/formula/live")?.host == "example.com")
    #expect(ServerConnection.timingURL(from: "") == nil)
    #expect(ServerConnection.timingURL(from: "http://localhost:8787/live") == nil)
    #expect(ServerConnection.timingURL(from: "localhost:8787") == nil)
    #expect(ServerConnection.timingURL(from: "ws://user:secret@example.com/live") == nil)
}

@Test func clearingTheAddressConnectsToAnEmptyAddressThatFailsValidation() {
    var connection = ServerConnection(endpoint: "ws://localhost:8787/live")
    connection.beginEditing()
    connection.draftEndpoint = "   "
    connection.connect()
    #expect(connection.activeEndpoint.isEmpty)
    #expect(ServerConnection.timingURL(from: connection.activeEndpoint) == nil)
}
