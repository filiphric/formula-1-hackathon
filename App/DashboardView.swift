import SwiftUI

struct DashboardView: View {
    @State private var store = TimingStore()
    @AppStorage("serverEndpoint") private var endpoint = "ws://localhost:8787/live"
    @State private var activeEndpoint = ""
    @State private var showingSettings = false
    private let accent = Color(red: 1, green: 0.22, blue: 0.18)

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
                        TrackMapView(snapshot: snapshot, connected: store.connected)
                        timingBoard(snapshot)
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
            .background(Color(red: 0.045, green: 0.05, blue: 0.065))
            .navigationTitle("Formula Live")
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RACE CENTRE").font(.caption.bold()).tracking(3).foregroundStyle(accent)
                Spacer()
                Label(store.snapshot?.mode == "demo" ? "DEMO" : store.status,
                      systemImage: store.connected ? "circle.fill" : "circle")
                    .font(.caption.bold()).foregroundStyle(store.connected ? .green : .secondary)
            }
            Text(store.snapshot?.session?.circuit ?? "Ready for lights out")
                .font(.largeTitle.bold())
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
    }

    private func timingBoard(_ snapshot: TimingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Timing board").font(.title3.bold())
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
                        Text(driver.acronym).font(.headline)
                        Text(driver.team).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(driver.gap ?? (driver.position == 1 ? "LEADER" : "—"))
                            .font(.subheadline.monospacedDigit())
                        Text(driver.formattedLap).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(driver.compound.map { String($0.prefix(1)) } ?? "—")
                        .font(.caption.bold()).frame(width: 24, height: 24)
                        .background(.white.opacity(0.08), in: Circle())
                        .accessibilityLabel(driver.compound ?? "Tyre unknown")
                }
                .accessibilityElement(children: .combine)
                if driver.id != snapshot.drivers.last?.id { Divider().opacity(0.4) }
            }
        }.padding(20).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
    }

    private func raceControl(_ snapshot: TimingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Race control", systemImage: "flag").font(.title3.bold())
            if snapshot.messages.isEmpty {
                Text("No race-control messages yet.").foregroundStyle(.secondary)
            }
            ForEach(snapshot.messages.prefix(10)) { message in
                Text(message.message).font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

}
