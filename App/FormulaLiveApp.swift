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

private enum AppTab: String, CaseIterable, Identifiable {
    case live = "Live timing", schedule = "Schedule"
    var id: Self { self }
    var symbol: String { self == .live ? "flag.checkered" : "calendar" }
}

private struct RootView: View {
    @AppStorage("serverEndpoint") private var endpoint = "ws://localhost:8787/live"
    @State private var store = TimingStore()
    @State private var activeEndpoint = ""
    @State private var showingSettings = false
    /// `-initialTab Schedule` on the command line opens that tab first; otherwise Live timing.
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tab = AppTab(rawValue: UserDefaults.standard.string(forKey: "initialTab") ?? "") ?? .live

    var body: some View {
        // One clock drives the app bar's pill and the session hero, so they can never disagree.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let feed = FeedStatus.resolve(snapshot: store.snapshot, connected: store.connected,
                                          hasError: store.error != nil, now: context.date)
            VStack(spacing: 0) {
                AppBar(feed: feed, tab: $tab, showsTabs: tabsInBar, showSettings: { showingSettings = true })
                content(feed: feed)
            }
        }
        .background(RacingStyle.background.ignoresSafeArea())
        .tint(RacingStyle.accentText)
        .sheet(isPresented: $showingSettings) { ConnectionSheet(endpoint: $endpoint) { connect() } }
        .task { activeEndpoint = endpoint }
        .task(id: activeEndpoint) {
            guard !activeEndpoint.isEmpty else { return }
            await store.run(endpoint: activeEndpoint)
        }
    }

    private func connect() {
        activeEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        showingSettings = false
    }

    /// Mac and iPad put the tab control in the app bar, so the window has one bar of chrome, not two.
    /// Phones keep the system bottom tab bar.
    private var tabsInBar: Bool {
        #if os(macOS)
        true
        #else
        sizeClass != .compact
        #endif
    }

    @ViewBuilder private func content(feed: FeedStatus) -> some View {
        let scheduleEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if tabsInBar {
            ZStack {
                DashboardView(store: store, feed: feed)
                    .opacity(tab == .live ? 1 : 0).allowsHitTesting(tab == .live).accessibilityHidden(tab != .live)
                ScheduleView(endpoint: scheduleEndpoint)
                    .opacity(tab == .schedule ? 1 : 0).allowsHitTesting(tab == .schedule).accessibilityHidden(tab != .schedule)
            }
        } else {
            TabView(selection: $tab) {
                DashboardView(store: store, feed: feed).tag(AppTab.live)
                    .tabItem { Label(AppTab.live.rawValue, systemImage: AppTab.live.symbol) }
                ScheduleView(endpoint: scheduleEndpoint).tag(AppTab.schedule)
                    .tabItem { Label(AppTab.schedule.rawValue, systemImage: AppTab.schedule.symbol) }
            }
        }
    }
}

/// The only app-level chrome: logo, name, feed status. One 3pt brand-red rule underneath is the
/// only accent in the header area.
private struct AppBar: View {
    let feed: FeedStatus
    @Binding var tab: AppTab
    let showsTabs: Bool
    let showSettings: () -> Void

    var body: some View {
        // Drop the wordmark before squeezing the pill. The bar's own text stops at xxxLarge:
        // it is chrome, and the content below it scales all the way up.
        ViewThatFits(in: .horizontal) {
            bar(showName: true)
            bar(showName: false)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, RacingStyle.Space.l)
        .frame(minHeight: 48)
        .background(RacingStyle.background, ignoresSafeAreaEdges: .top)
        .overlay(alignment: .bottom) { RacingStyle.red.frame(height: 3) }
    }

    private func bar(showName: Bool) -> some View {
        HStack(spacing: RacingStyle.Space.m) {
            Image(systemName: "flag.checkered").font(RacingStyle.Typography.title).foregroundStyle(RacingStyle.red)
                .accessibilityHidden(true)
            if showName {
                Text("FORMULA LIVE").font(RacingStyle.Typography.headline).italic()
                    .lineLimit(1).fixedSize()
                    .accessibilityAddTraits(.isHeader)
            }
            if showsTabs {
                Picker("Section", selection: $tab) {
                    ForEach(AppTab.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize().padding(.leading, RacingStyle.Space.m)
            }
            Spacer(minLength: RacingStyle.Space.s)
            FeedStatusPill(status: feed)
            Button(action: showSettings) {
                Image(systemName: "network").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(RacingStyle.textSecondary)
                .accessibilityLabel("Connection settings")
        }
    }
}

private struct ConnectionSheet: View {
    @Binding var endpoint: String
    let connect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RacingStyle.Space.l) {
            Text("Timing server").font(RacingStyle.Typography.title)
            Text("Use localhost on your Mac or iOS Simulator. On an iPhone, use your Mac’s local network address.")
                .font(RacingStyle.Typography.body).foregroundStyle(RacingStyle.textSecondary)
            TextField("ws://localhost:8787/live", text: $endpoint)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            Text("OpenF1 credentials stay on the backend.")
                .font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
            Button("Connect", action: connect).buttonStyle(.borderedProminent).tint(RacingStyle.red)
        }.padding(RacingStyle.Space.xl).frame(minWidth: 300, idealWidth: 440)
    }
}
