import SwiftUI

@main
struct FormulaLiveApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .defaultSize(width: 1080, height: 760)
        #endif
    }
}

private struct RootView: View {
    @AppStorage("serverEndpoint") private var endpoint = "ws://localhost:8787/live"

    @State private var connection = ServerConnection(endpoint: "")

    var body: some View {
        TabView {
            DashboardView(connection: $connection).tabItem { Label("Live timing", systemImage: "flag.checkered") }
            ScheduleView(endpoint: connection.activeEndpoint)
                .tabItem { Label("Schedule", systemImage: "calendar") }
        }.tint(.red)
        .task {
            if connection.activeEndpoint.isEmpty { connection = ServerConnection(endpoint: endpoint) }
        }
        .onChange(of: connection.activeEndpoint) { _, value in endpoint = value }
    }
}
