import Foundation
import Observation

@MainActor @Observable
final class ScheduleStore {
    var schedule: RaceSchedule?
    var loading = false
    var error: String?
    private var requestID = UUID()

    func load(endpoint: String, season: Int) async {
        let id = UUID()
        requestID = id
        schedule = nil
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
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard requestID == id else { return }
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let result = try JSONDecoder().decode(RaceSchedule.self, from: data)
            guard result.season == season else { throw URLError(.cannotParseResponse) }
            schedule = result
        } catch {
            if !Task.isCancelled && requestID == id {
                self.error = "Calendar unavailable. Check your backend connection and try again."
            }
        }
    }
}
