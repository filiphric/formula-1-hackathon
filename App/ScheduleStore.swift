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
    /// Changes whenever saved results are discarded, so cards that are already open ask again.
    private(set) var generation = 0
    private var scope = ""
    /// Requests belong to the store, not to the card that started them: folding a card never cancels
    /// one, and reopening the card joins it instead of starting another.
    private var inflight: [Int: Task<Void, Never>] = [:]

    /// Loads one round. A published classification is kept; a failed or not-yet-published one is asked for again.
    func load(round: Int, endpoint: String, season: Int) async {
        let key = "\(endpoint)|\(season)"
        if scope != key { scope = key; discard() }
        if case .loaded(let saved)? = phases[round], !saved.entries.isEmpty { return }
        if let running = inflight[round] { await running.value; return }
        guard let url = RaceResults.endpoint(from: endpoint, season: season, round: round) else {
            phases[round] = .failed
            return
        }
        switch phases[round] {
        case .loaded?: break // Keep showing "not published yet" while asking again.
        default: phases[round] = .loading
        }
        let generation = generation
        let request = Task { await fetch(url: url, season: season, round: round, generation: generation) }
        inflight[round] = request
        await request.value
    }

    private func fetch(url: URL, season: Int, round: Int, generation: Int) async {
        var phase = Phase.failed
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
            phase = .loaded(result)
        } catch {}
        // Results discarded while the request was out (refresh, other season) are not for this store any more.
        guard generation == self.generation else { return }
        phases[round] = phase
        inflight[round] = nil
    }

    /// Forget one round, so the next `load` asks the backend again.
    func retry(round: Int) { phases[round] = nil }

    func reset() { discard() }

    private func discard() {
        phases = [:]
        inflight = [:]
        generation += 1
    }
}
