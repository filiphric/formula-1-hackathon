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

    var body: some View {
        TabView {
            DashboardView().tabItem { Label("Live timing", systemImage: "flag.checkered") }
            ScheduleView(endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))
                .tabItem { Label("Schedule", systemImage: "calendar") }
        }.tint(.red)
    }
}
