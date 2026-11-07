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
    @State private var store = TimingStore()
    @State private var activeEndpoint = ""
    @State private var showingSettings = false
    /// `-initialTab Schedule` on the command line opens that tab first; otherwise Live timing.
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tab = AppSection(rawValue: UserDefaults.standard.string(forKey: "initialTab") ?? "") ?? .live

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
                DashboardView(store: store, feed: feed).tag(AppSection.live)
                    .tabItem { Image(systemName: AppSection.live.symbol).accessibilityLabel(AppSection.live.rawValue) }
                ScheduleView(endpoint: scheduleEndpoint).tag(AppSection.schedule)
                    .tabItem { Image(systemName: AppSection.schedule.symbol).accessibilityLabel(AppSection.schedule.rawValue) }
            }
        }
    }
}

/// Icon navigation, feed status on the live screen, and connection settings.
private struct AppBar: View {
    let feed: FeedStatus
    @Binding var tab: AppSection
    let showsTabs: Bool
    let showSettings: () -> Void

    var body: some View {
        bar
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.horizontal, RacingStyle.Space.l)
            .frame(minHeight: 48)
            .background(RacingStyle.background, ignoresSafeAreaEdges: .top)
            .overlay(alignment: .bottom) { RacingStyle.red.frame(height: 3) }
    }

    private var bar: some View {
        HStack(spacing: RacingStyle.Space.m) {
            Image("F1Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 16)
                .accessibilityLabel("Formula 1")
            if showsTabs {
                HStack(spacing: RacingStyle.Space.xs) {
                    ForEach(AppSection.allCases) { section in
                        Button { tab = section } label: {
                            Image(systemName: section.symbol)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(tab == section ? RacingStyle.raised : .clear, in: RoundedRectangle(cornerRadius: RacingStyle.Radius.row))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(tab == section ? RacingStyle.textPrimary : RacingStyle.textSecondary)
                        .accessibilityLabel(section.rawValue)
                        .accessibilityAddTraits(tab == section ? .isSelected : [])
                        .help(section.rawValue)
                    }
                }
            }
            Spacer(minLength: RacingStyle.Space.s)
            // The feed pill describes the live timing connection, so it only appears on that screen.
            if tab.showsFeedStatus { FeedStatusPill(status: feed) }
            Button(action: showSettings) {
                Image(systemName: "gearshape")
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(RacingStyle.textSecondary)
                .accessibilityLabel("Connection settings").help("Connection settings")
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
            Button(action: connect) {
                Label("Connect", systemImage: "arrow.right").labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }.buttonStyle(.borderedProminent).tint(RacingStyle.red).help("Connect")
        }.padding(RacingStyle.Space.xl).frame(minWidth: 300, idealWidth: 440)
    }
}
