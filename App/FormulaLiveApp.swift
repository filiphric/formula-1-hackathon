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

extension AppSection {
    var symbol: String { self == .live ? "flag.checkered" : "calendar" }
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
                DashboardView(store: store, feed: feed)
                    .opacity(tab == .live ? 1 : 0).allowsHitTesting(tab == .live).accessibilityHidden(tab != .live)
                ScheduleView(endpoint: scheduleEndpoint)
                    .opacity(tab == .schedule ? 1 : 0).allowsHitTesting(tab == .schedule).accessibilityHidden(tab != .schedule)
            }
        } else {
            TabView(selection: $tab) {
                DashboardView(store: store, feed: feed).tag(AppSection.live)
                    .tabItem { Label(AppSection.live.rawValue, systemImage: AppSection.live.symbol) }
                ScheduleView(endpoint: scheduleEndpoint).tag(AppSection.schedule)
                    .tabItem { Label(AppSection.schedule.rawValue, systemImage: AppSection.schedule.symbol) }
            }
        }
    }
}

/// The only app-level chrome: logo, name, feed status (live screen only), connection settings. One 3pt brand-red rule underneath is the
/// only accent in the header area.
private struct AppBar: View {
    let feed: FeedStatus
    @Binding var tab: AppSection
    let showsTabs: Bool
    let showSettings: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

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
                    ForEach(AppSection.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize().padding(.leading, RacingStyle.Space.m)
            }
            Spacer(minLength: RacingStyle.Space.s)
            // The feed pill describes the live timing connection, so it only appears on that screen.
            if tab.showsFeedStatus { FeedStatusPill(status: feed) }
            Button(action: showSettings) {
                HStack(spacing: RacingStyle.Space.xs) {
                    Image(systemName: "gearshape")
                    // Phones keep just the icon to save width; wider screens say what it is.
                    if sizeClass != .compact { Text("Connection").font(RacingStyle.Typography.caption.weight(.semibold)).lineLimit(1) }
                }
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
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
