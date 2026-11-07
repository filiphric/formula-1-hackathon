import Foundation
import Testing
@testable import FormulaCore

private func freshDefaults() -> UserDefaults {
    let suite = "ServerEndpointSeedTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Test func seedSavesALanAddressAsTheServerSetting() {
    let defaults = freshDefaults()
    #expect(ServerEndpointSeed.apply(" ws://192.168.1.102:8789/live \n", to: defaults))
    #expect(defaults.string(forKey: "serverEndpoint") == "ws://192.168.1.102:8789/live")
    #expect(ServerEndpointSeed.apply("wss://f1.example.com/live", to: defaults))
    #expect(defaults.string(forKey: "serverEndpoint") == "wss://f1.example.com/live")
}

@Test func seedNeverReplacesTheSavedAddressWithSomethingUnusable() {
    let defaults = freshDefaults()
    defaults.set("ws://saved:8787/live", forKey: "serverEndpoint")
    for bad in [nil, "", "   ", "http://192.168.1.102:8789/live", "192.168.1.102:8789", "ws://", "not a url"] as [String?] {
        #expect(!ServerEndpointSeed.apply(bad, to: defaults), "\(bad ?? "nil") must be rejected")
    }
    #expect(defaults.string(forKey: "serverEndpoint") == "ws://saved:8787/live")
}
