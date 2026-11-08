import SwiftUI

@main
struct FormulaLiveApp: App {
    init() {
        // `-seedServerEndpoint ws://host:port/live` saves a one-time address (see Scripts/install-iphone.sh).
        ServerEndpointSeed.apply(UserDefaults.standard.string(forKey: ServerEndpointSeed.launchKey),
                                 to: .standard)
    }

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
    @State private var showingSettings = false
    /// `-initialTab Schedule` on the command line opens that tab first; otherwise Live timing.
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tab = AppSection(rawValue: UserDefaults.standard.string(forKey: "initialTab") ?? "") ?? .live

    @State private var connection = ServerConnection(endpoint: "")
    /// The saved address is read once at launch. After that an empty address is a real choice and gets validated, not skipped.
    @State private var seeded = false

    var body: some View {
        // One clock drives the app bar's pill and the session hero, so they can never disagree.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let feed = FeedStatus.resolve(snapshot: store.snapshot, connected: store.connected,
                                          hasError: store.error != nil, now: context.date)
            VStack(spacing: 0) {
                AppBar(feed: feed, tab: $tab, showsTabs: tabsInBar, showSettings: { connection.beginEditing(); showingSettings = true })
                // Under the bar and outside the scrolling pages, so a flag is in view on every tab and while scrolling.
                FlagBanner(snapshot: store.snapshot, feed: feed, now: context.date)
                content(feed: feed)
            }
        }
        .background(RacingStyle.background.ignoresSafeArea())
        .tint(RacingStyle.accentText)
        .sheet(isPresented: $showingSettings) {
            ConnectionSheet(endpoint: $connection.draftEndpoint) {
                connection.connect()
                showingSettings = false
            }
        }
        .task {
            connection = ServerConnection(endpoint: endpoint)
            seeded = true
        }
        .task(id: "\(seeded)|\(connection.activeEndpoint)") {
            guard seeded else { return }
            await store.run(endpoint: connection.activeEndpoint)
        }
        .onChange(of: connection.activeEndpoint) { _, value in endpoint = value }
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
        let scheduleEndpoint = connection.activeEndpoint
        if tabsInBar {
            ZStack {
                DashboardView(store: store, feed: feed, endpoint: scheduleEndpoint, isActive: tab == .live)
                    .opacity(tab == .live ? 1 : 0).allowsHitTesting(tab == .live).accessibilityHidden(tab != .live)
                ScheduleView(endpoint: scheduleEndpoint)
                    .opacity(tab == .schedule ? 1 : 0).allowsHitTesting(tab == .schedule).accessibilityHidden(tab != .schedule)
            }
        } else {
            TabView(selection: $tab) {
                DashboardView(store: store, feed: feed, endpoint: scheduleEndpoint, isActive: tab == .live).tag(AppSection.live)
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
            VStack(spacing: RacingStyle.Space.xs) {
                Image("F1Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 16)
                Text("Unofficial")
                    .font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            // Logo (16) + gap (4) + caption (about 18 at the bar's xxxLarge cap) is 38pt. This 40pt block fits that and
            // stays under the bar's 48pt minimum, so the disclosure never changes the bar height or the tabs' alignment.
            .frame(width: 64, height: 40)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Unofficial Formula 1 companion")
            .help("Unofficial Formula 1 companion · Powered by OpenF1")
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
