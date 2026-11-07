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
                            .font(.callout).foregroundStyle(.orange)
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
                        .font(.caption).foregroundStyle(.secondary)
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
                        .font(.callout).foregroundStyle(.secondary)
                    TextField("ws://localhost:8787/live", text: $endpoint)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    Text("OpenF1 credentials stay on the backend.")
                        .font(.caption).foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("RACE CENTRE", systemImage: "flag.checkered").font(.caption.bold()).tracking(2).foregroundStyle(.white)
                Spacer()
                Label(store.snapshot?.mode == "demo" ? "DEMO" : store.status,
                      systemImage: store.connected ? "circle.fill" : "circle")
                    .font(.caption.bold()).foregroundStyle(store.snapshot?.mode == "demo" ? .orange : store.connected ? .green : .secondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.black.opacity(0.25), in: Capsule())
            }
            Text(store.snapshot?.session?.circuit ?? "Ready for lights out")
                .font(.system(.largeTitle, design: .rounded, weight: .black))
            HStack {
                Text(store.snapshot?.session?.name ?? "Live timing for macOS and iOS")
                Spacer()
                if let snapshot = store.snapshot {
                    Text("Feed: \(snapshot.upstream)")
                }
            }.font(.subheadline).foregroundStyle(.secondary)
            if store.snapshot?.mode == "demo" {
                Text("Sample timing · Live access is configured on the backend")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let updated = store.snapshot?.updatedAt,
               let date = ISO8601DateFormatter().date(from: updated) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let stale = context.date.timeIntervalSince(date) > 30
                    Text(stale ? "No new timing for over 30 seconds" : "Latest timing \(date.formatted(date: .omitted, time: .standard))")
                        .font(.caption).foregroundStyle(stale ? .orange : .secondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.02, blue: 0.02), RacingStyle.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { RacingStripes().clipShape(RoundedRectangle(cornerRadius: 12)) }
        }
        .overlay(alignment: .leading) { UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12).fill(accent).frame(width: 4) }
    }

    private func timingBoard(_ snapshot: TimingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            RacingSectionTitle(title: "Leaderboard", subtitle: "Position / driver / gap / last lap")
            HStack {
                Text("POS").frame(width: 30)
                Text("DRIVER")
                Spacer()
                Text("GAP / LAP")
                Text("TYRE").padding(.leading, 6)
            }.font(.system(.caption2, weight: .bold)).foregroundStyle(.secondary)
            if snapshot.drivers.isEmpty {
                Text("Waiting for driver data…").foregroundStyle(.secondary)
            }
            ForEach(snapshot.drivers) { driver in
                HStack(spacing: 12) {
                    Text(driver.position.map(String.init) ?? "—")
                        .font(.title3.bold().monospacedDigit()).frame(width: 30)
                    RoundedRectangle(cornerRadius: 2).fill(Color.team(driver.color))
                        .frame(width: 4, height: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(driver.acronym).font(.system(.headline, design: .rounded, weight: .heavy))
                        Text(driver.team).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(driver.gap ?? (driver.position == 1 ? "LEADER" : "—"))
                            .font(.subheadline.monospacedDigit())
                        Text(driver.formattedLap).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    TyreBadge(compound: TyreCompound(driver.compound))
                }
                .accessibilityElement(children: .combine)
                if driver.id != snapshot.drivers.last?.id { Divider().opacity(0.4) }
            }
        }.racingCard()
    }

    private func raceControl(_ snapshot: TimingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            RacingSectionTitle(title: "Race control", subtitle: "Latest messages from the session")
            if snapshot.messages.isEmpty {
                Text("No race-control messages yet.").foregroundStyle(.secondary)
            }
            ForEach(snapshot.messages.prefix(10)) { message in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "flag.fill").foregroundStyle(.secondary).padding(.top, 2)
                    Text(message.message).font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(14).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }
        }.racingCard()
    }

}
