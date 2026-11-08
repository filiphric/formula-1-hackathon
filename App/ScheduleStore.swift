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
            let requestStarted = ContinuousClock.now
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
            validatedAt = requestStarted
        } catch {
            if !Task.isCancelled && requestID == id {
                refreshFailed = schedule != nil
                self.error = "Calendar unavailable. Check your backend connection and try again."
            }
        }
    }
}

/// Race results, fetched the first time a finished weekend is opened and kept for the season being shown.
@MainActor @Observable
final class ResultsStore {
    enum Phase { case loading, loaded(RaceResults), failed }
    private(set) var phases: [Int: Phase] = [:]
    private var scope = ""

    /// Loads one round unless it is already loading or loaded. A failed round is retried on the next call.
    func load(round: Int, endpoint: String, season: Int) async {
        let key = "\(endpoint)|\(season)"
        if scope != key { scope = key; phases = [:] }
        switch phases[round] {
        case .loading, .loaded: return
        default: break
        }
        guard let url = RaceResults.endpoint(from: endpoint, season: season, round: round) else {
            phases[round] = .failed
            return
        }
        phases[round] = .loading
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 25
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let result = try JSONDecoder().decode(RaceResults.self, from: data)
            guard result.season == season, result.round == round else { throw URLError(.cannotParseResponse) }
            if scope == key { phases[round] = .loaded(result) }
        } catch {
            // A cancelled load (the card folded, the season changed) is not a failure to show.
            if scope == key { phases[round] = Task.isCancelled ? nil : .failed }
        }
    }

    /// Forget one round, so the next `load` asks the backend again.
    func retry(round: Int) { phases[round] = nil }

    func reset() { phases = [:] }
}
