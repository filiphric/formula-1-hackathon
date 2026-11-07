import SwiftUI

struct TrackMapView: View {
    let snapshot: TimingSnapshot
    let connected: Bool
    @State private var selectedDriver: Int?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        RacingSectionTitle(title: "Driver tracker", subtitle: "On track · Approximate positions")
                        Spacer()
                        driverPicker
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        RacingSectionTitle(title: "Driver tracker", subtitle: "On track · Approximate positions")
                        driverPicker
                    }
                }
                Text(snapshot.trackStatus(at: context.date, connected: connected))
                    .font(.caption.bold()).foregroundStyle(snapshot.mode == "demo" ? .orange : .secondary)
                if let track = snapshot.track {
                    map(track, now: context.date).frame(height: 340)
                    Text(track.source).font(.caption).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("Waiting for track layout", systemImage: "map",
                        description: Text("The circuit outline appears after a complete timed lap is available. Driver locations require a backend with track support."))
                        .frame(minHeight: 220)
                }
                legend(now: context.date)
                Text("Approximate positions · Dimmed markers are over 10 seconds old. Drivers without coordinates are listed as unavailable.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .racingCard()
        }
        .onChange(of: snapshot.session?.start) { selectedDriver = nil }
    }

    private var driverPicker: some View {
        Picker("Follow driver", selection: $selectedDriver) {
            Text("All drivers").tag(Int?.none)
            ForEach(snapshot.drivers) { driver in
                Text("\(driver.number) · \(driver.acronym)").tag(Optional(driver.number))
            }
        }.fixedSize()
    }

    private func map(_ track: TrackLayout, now: Date) -> some View {
        GeometryReader { geometry in
            if let projection = track.projection(width: geometry.size.width, height: geometry.size.height) {
                ZStack {
                    RacingStripes().opacity(0.6)
                    Path { path in
                        for (index, point) in track.points.enumerated() {
                            if let mapped = projection.project(x: point.x, y: point.y) {
                                let position = CGPoint(x: mapped.x, y: mapped.y)
                                if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                            }
                        }
                    }.stroke(.gray.opacity(0.55), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                    ForEach(snapshot.drivers) { driver in
                        if let location = driver.location,
                           let point = projection.project(x: location.x, y: location.y) {
                            let stale = location.isStale(at: now)
                            Button { selectedDriver = selectedDriver == driver.number ? nil : driver.number } label: {
                                Text(String(driver.number)).font(.caption2.bold().monospacedDigit())
                                    .foregroundStyle(.white).frame(width: 28, height: 28)
                                    .background(Color.team(driver.color), in: Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: selectedDriver == driver.number ? 3 : 1))
                            }
                            .buttonStyle(.plain)
                            .opacity(stale ? 0.35 : selectedDriver == nil || selectedDriver == driver.number ? 1 : 0.4)
                            .position(x: point.x, y: point.y)
                            .zIndex(selectedDriver == driver.number ? 1 : 0)
                            .accessibilityLabel("\(driver.name), car \(driver.number), \(stale ? "stale location" : "location received"), \(location.date)")
                        }
                    }
                }.clipped()
            } else {
                ContentUnavailableView("Track layout unavailable", systemImage: "map")
            }
        }
    }

    private func legend(now: Date) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 10) {
            ForEach(snapshot.drivers.filter { selectedDriver == nil || $0.number == selectedDriver }) { driver in
                HStack(spacing: 7) {
                    Circle().fill(Color.team(driver.color)).frame(width: 8, height: 8)
                    Text("\(driver.number) \(driver.acronym)").fontWeight(.semibold)
                    Text(driver.location.map { $0.isStale(at: now) ? "Stale" : "Located" } ?? "Unavailable")
                        .foregroundStyle(.secondary)
                }.font(.caption).accessibilityElement(children: .combine)
            }
        }
    }

}

extension Color {
    static func team(_ hex: String) -> Color {
        guard let value = UInt(hex, radix: 16) else { return .gray }
        return Color(red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255,
                     blue: Double(value & 255) / 255)
    }
}
