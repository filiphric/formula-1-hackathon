import SwiftUI

struct DashboardView: View {
    @State private var store = TimingStore()
    @AppStorage("serverEndpoint") private var endpoint = "ws://localhost:8787/live"
    @State private var activeEndpoint = ""
    @State private var showingSettings = false
    private let accent = RacingStyle.red

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if let error = store.error {
                        Label(error, systemImage: "wifi.exclamationmark")
                            .font(.callout).foregroundStyle(Color(RacingPalette.statusStale))
                    }
                    if let snapshot = store.snapshot {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 20) {
                                timingBoard(snapshot).frame(width: 390)
                                TrackMapView(snapshot: snapshot, connected: store.connected).frame(minWidth: 420)
                            }
                            VStack(spacing: 20) {
                                timingBoard(snapshot)
                                TrackMapView(snapshot: snapshot, connected: store.connected)
                            }
                        }
                        raceControl(snapshot)
                    } else {
                        ContentUnavailableView(
                            "Your race weekend, live",
                            systemImage: "flag.checkered",
                            description: Text("Start the backend to load timing. Demo mode works without OpenF1 credentials.")
                        ).frame(minHeight: 280)
                    }
                    Text("Powered by OpenF1 · Unofficial Formula 1 companion")
                        .font(.caption).foregroundStyle(RacingStyle.textTertiary)
                }.padding(24).frame(maxWidth: 1200)
                    .frame(maxWidth: .infinity)
            }
            .background(RacingStyle.background)
            .navigationTitle("Race centre")
            .toolbar {
                Button("Connection", systemImage: "network") { showingSettings = true }
            }
            .sheet(isPresented: $showingSettings) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Timing server").font(.title2.bold())
                    Text("Use localhost on your Mac or iOS Simulator. On an iPhone, use your Mac’s local network address.")
                        .font(.callout).foregroundStyle(RacingStyle.textSecondary)
                    TextField("ws://localhost:8787/live", text: $endpoint)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    Text("OpenF1 credentials stay on the backend.")
                        .font(.caption).foregroundStyle(RacingStyle.textSecondary)
                    Button("Connect") {
                        activeEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
                        showingSettings = false
                    }.buttonStyle(.borderedProminent).tint(accent)
                }.padding(28).frame(minWidth: 300, idealWidth: 440)
            }
            .task { activeEndpoint = endpoint }
            .task(id: activeEndpoint) {
                guard !activeEndpoint.isEmpty else { return }
                await store.run(endpoint: activeEndpoint)
            }
        }
    }

    private var header: some View {
        // One clock drives both the pill and the caption so they can never disagree.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let feed = FeedStatus.resolve(snapshot: store.snapshot, connected: store.connected,
                                          hasError: store.error != nil, now: context.date)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("RACE CENTRE", systemImage: "flag.checkered").font(.caption.bold()).tracking(2)
                        .foregroundStyle(RacingStyle.textPrimary)
                    Spacer()
                    FeedStatusPill(status: feed)
                }
                Text(store.snapshot?.session?.circuit ?? "Ready for lights out")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                HStack {
                    Text(store.snapshot?.session?.name ?? "Live timing for macOS and iOS")
                    Spacer()
                    if let snapshot = store.snapshot {
                        Text("Feed: \(snapshot.upstream)")
                    }
                }.font(.subheadline).foregroundStyle(RacingStyle.textSecondary)
                headerCaption(feed)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [RacingStyle.headerRed, RacingStyle.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay { RacingStripes().clipShape(RoundedRectangle(cornerRadius: 12)) }
            }
            .overlay(alignment: .leading) { UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12).fill(accent).frame(width: 4) }
        }
    }

    @ViewBuilder private func headerCaption(_ feed: FeedStatus) -> some View {
        if feed.isDemo {
            Text("Sample timing · Live access is configured on the backend")
                .font(.caption).foregroundStyle(RacingStyle.textSecondary)
        } else if feed.kind == .stale, let age = feed.age {
            Text("No new timing for \(Int(age)) seconds")
                .font(.caption).foregroundStyle(Color(RacingPalette.statusStale))
        } else if feed.kind == .offline {
            Text("Showing the last timing received. Reconnecting…")
                .font(.caption).foregroundStyle(Color(RacingPalette.statusStale))
        } else if let date = feed.updatedAt {
            Text("Latest timing \(date.formatted(date: .omitted, time: .standard))")
                .font(.caption).foregroundStyle(RacingStyle.textSecondary)
        }
    }

    private func timingBoard(_ snapshot: TimingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            RacingSectionTitle(title: "Leaderboard", subtitle: "Position / driver / gap / last lap")
            if snapshot.drivers.isEmpty {
                Text("Waiting for driver data…").foregroundStyle(RacingStyle.textSecondary)
            }
            // Keep every timing column reachable at narrow widths and large text sizes.
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                    GridRow {
                        Text("POS")
                        Color.clear.frame(width: 4, height: 1).accessibilityHidden(true)
                        Text("DRIVER")
                        Text("GAP / LAP").gridColumnAlignment(.trailing)
                        Text("TYRE").gridColumnAlignment(.center)
                    }.font(.system(.caption2, weight: .bold)).foregroundStyle(RacingStyle.textSecondary)
                        .accessibilityHidden(true)
                    ForEach(snapshot.drivers) { driver in
                        GridRow {
                            Text(driver.position.map(String.init) ?? "—")
                                .font(.title3.bold().monospacedDigit())
                            RoundedRectangle(cornerRadius: 2).fill(Color.team(driver.color))
                                .frame(width: 4, height: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(driver.acronym).font(.system(.headline, design: .rounded, weight: .heavy))
                                Text(driver.team).font(.caption).foregroundStyle(RacingStyle.textSecondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(driver.gap ?? (driver.position == 1 ? "LEADER" : "—"))
                                    .font(.subheadline.monospacedDigit())
                                Text(driver.formattedLap).font(.caption.monospacedDigit()).foregroundStyle(RacingStyle.textSecondary)
                            }
                            TyreBadge(compound: TyreCompound(driver.compound))
                        }.accessibilityElement(children: .ignore)
                        .accessibilityLabel(driver.accessibilitySummary)
                        if driver.id != snapshot.drivers.last?.id {
                            Divider().overlay(RacingStyle.raised).gridCellUnsizedAxes(.horizontal)
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }.racingCard()
    }

    private func raceControl(_ snapshot: TimingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            RacingSectionTitle(title: "Race control", subtitle: "Latest messages from the session")
            if snapshot.messages.isEmpty {
                Text("No race-control messages yet.").foregroundStyle(RacingStyle.textSecondary)
            }
            ForEach(snapshot.messages.prefix(10)) { message in
                raceControlRow(message)
            }
        }.racingCard()
    }

    private func raceControlRow(_ message: RaceMessage) -> some View {
        let kind = message.kind
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind.symbol).foregroundStyle(kind.color)
                .frame(width: 22).padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    // The label repeats what the colour says, so the flag is never colour-only.
                    Text(kind.label.uppercased()).font(.caption.bold()).foregroundStyle(kind.color)
                    if let time = message.timestamp {
                        Text(time.formatted(date: .omitted, time: .standard))
                            .font(.caption.monospacedDigit()).foregroundStyle(RacingStyle.textSecondary)
                    }
                }
                Text(message.message).font(.callout).foregroundStyle(RacingStyle.textPrimary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(RacingStyle.raised, in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            if kind.severity >= .caution { Rectangle().fill(kind.color).frame(width: 3) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.label). \(message.message)")
    }

}
