import Foundation
import Observation

@MainActor @Observable
final class TimingStore {
    var snapshot: TimingSnapshot?
    var status = "Disconnected"
    var error: String?
    var connected = false
    private var socket: URLSessionWebSocketTask?

    func run(endpoint: String) async {
        guard let url = URL(string: endpoint),
              ["ws", "wss"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else {
            error = "Enter a WebSocket address, such as ws://localhost:8787/live."
            return
        }
        snapshot = nil
        var retry = 1
        while !Task.isCancelled {
            status = retry == 1 ? "Connecting…" : "Reconnecting…"
            let connection = URLSession.shared.webSocketTask(with: url)
            socket = connection
            connection.resume()
            do {
                try await withTaskCancellationHandler {
                    while !Task.isCancelled {
                        let message = try await connection.receive()
                        let data: Data
                        switch message {
                        case .data(let value): data = value
                        case .string(let value): data = Data(value.utf8)
                        @unknown default: continue
                        }
                        // Decode off the main actor so a large snapshot never stalls scrolling.
                        snapshot = try await Task.detached(priority: .userInitiated) { try TimingSnapshot.decode(data) }.value
                        connected = true
                        status = "Connected"
                        error = nil
                        retry = 1
                    }
                } onCancel: {
                    connection.cancel(with: .goingAway, reason: nil)
                }
            } catch {
                if !Task.isCancelled {
                    self.error = "Cannot reach the timing server. Check its address and that the backend is running."
                }
            }
            connection.cancel(with: .goingAway, reason: nil)
            connected = false
            if Task.isCancelled { break }
            status = "Reconnecting in \(retry)s"
            do { try await Task.sleep(for: .seconds(retry)) } catch { break }
            retry = min(retry * 2, 30)
        }
        status = "Disconnected"
    }
}
