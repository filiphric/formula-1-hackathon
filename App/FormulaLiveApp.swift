import SwiftUI

@main
struct FormulaLiveApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .defaultSize(width: 1080, height: 760)
        #endif
    }
}
