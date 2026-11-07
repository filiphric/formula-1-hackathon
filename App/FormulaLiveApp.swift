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
        }
        .tint(RacingStyle.accentText)
        #if os(macOS)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "flag.checkered").font(.title2.bold()).foregroundStyle(RacingStyle.red)
                Text("FORMULA LIVE").font(.system(.headline, design: .rounded, weight: .black)).italic()
                Spacer()
                ViewThatFits(in: .horizontal) {
                    Text("RACE WEEKEND COMPANION").font(.caption2.bold()).tracking(1.5)
                        .foregroundStyle(RacingStyle.textSecondary).fixedSize()
                    Color.clear.frame(width: 0, height: 0)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .background(RacingStyle.background.overlay { RacingStripes() })
            .overlay(alignment: .bottom) { RacingStyle.red.frame(height: 3) }
        }
        #endif
    }
}
