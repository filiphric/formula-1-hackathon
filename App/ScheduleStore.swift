import Foundation
import Observation
#if SWIFT_PACKAGE
import FormulaCore
#endif

@MainActor @Observable
final class ScheduleStore {
    var schedule: RaceSchedule?
    var loading = false
    var error: String?
    var refreshFailed = false
    private var loadedKey: String?
    private var validatedAt: ContinuousClock.Instant?
    private let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
        try await URLSession.shared.data(for: $0)
    }) {
        self.fetch = fetch
    }
    private var requestID = UUID()

    func calendarIsStale() -> Bool {
        guard let schedule, let validatedAt else { return true }
        let elapsed = validatedAt.duration(to: .now)
        return refreshFailed || schedule.isStale(elapsedSinceValidation: Double(elapsed.components.seconds))
    }

    func load(endpoint: String, season: Int) async {
        let id = UUID()
        requestID = id
        let key = "\(endpoint)|\(season)"
        if loadedKey != key {
            schedule = nil
            validatedAt = nil
        }
        refreshFailed = false
        error = nil
        loading = true
        defer { if requestID == id { loading = false } }
        guard let url = RaceSchedule.endpoint(from: endpoint, season: season) else {
            error = "Set a valid timing server address in Connection."
            return
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 25
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await fetch(request)
            try Task.checkCancellation()
            guard requestID == id else { return }
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let result = try JSONDecoder().decode(RaceSchedule.self, from: data)
            guard result.season == season else { throw URLError(.cannotParseResponse) }
            schedule = result
            loadedKey = key
            validatedAt = .now
        } catch {
            if !Task.isCancelled && requestID == id {
                refreshFailed = schedule != nil
                self.error = "Calendar unavailable. Check your backend connection and try again."
            }
        }
    }
}
