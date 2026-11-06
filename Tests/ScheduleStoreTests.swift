import Foundation
import Testing
@testable import FormulaAppState

private actor CalendarResponses {
    private var calls = 0
    let data: Data

    init(data: Data) { self.data = data }

    func next(_ request: URLRequest) throws -> (Data, URLResponse) {
        calls += 1
        guard calls == 1 else { throw URLError(.notConnectedToInternet) }
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@Test @MainActor func failedRefreshRetainsOnlyTheSameServersSeason() async throws {
    let url = Bundle.module.url(forResource: "schedule", withExtension: "json", subdirectory: "Fixtures")!
    let responses = CalendarResponses(data: try Data(contentsOf: url))
    let store = ScheduleStore(fetch: { try await responses.next($0) })
    await store.load(endpoint: "ws://first.example/live", season: 2026)
    #expect(store.schedule?.races.count == 2)
    #expect(store.error == nil)
    await store.load(endpoint: "ws://first.example/live", season: 2026)
    #expect(store.schedule?.races.count == 2)
    #expect(store.refreshFailed)
    #expect(store.error != nil)
    await store.load(endpoint: "ws://second.example/live", season: 2026)
    #expect(store.schedule == nil)
    #expect(!store.refreshFailed)
    #expect(store.error != nil)
}

@Test @MainActor func clearingConfirmedServerClearsThePreviousCalendar() async throws {
    let url = Bundle.module.url(forResource: "schedule", withExtension: "json", subdirectory: "Fixtures")!
    let responses = CalendarResponses(data: try Data(contentsOf: url))
    let store = ScheduleStore(fetch: { try await responses.next($0) })
    await store.load(endpoint: "ws://first.example/live", season: 2026)
    #expect(store.schedule != nil)
    await store.load(endpoint: "", season: 2026)
    #expect(store.schedule == nil)
    #expect(store.error != nil)
}
