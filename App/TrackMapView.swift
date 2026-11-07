import SwiftUI

struct TrackMapView: View {
    let snapshot: TimingSnapshot
    let connected: Bool
    @State private var selectedDriver: Int?
    @ScaledMetric(relativeTo: .caption) private var markerSize = 28
    @ScaledMetric(relativeTo: .caption) private var labelWidth = 48
    @ScaledMetric(relativeTo: .caption) private var labelHeight = 22

    private let kerbWidth: CGFloat = 22
    private let surfaceWidth: CGFloat = 12

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        RacingSectionTitle(title: "Driver tracker", subtitle: "Approximate positions")
                        Spacer()
                        driverPicker
                    }
                    VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
                        RacingSectionTitle(title: "Driver tracker", subtitle: "Approximate positions")
                        driverPicker
                    }
                }
                Text(snapshot.trackStatus(at: context.date, connected: connected))
                    .font(RacingStyle.Typography.label)
                    .foregroundStyle(snapshot.mode == "demo" ? Color(RacingPalette.statusDemo) : RacingStyle.textSecondary)
                if let track = snapshot.track {
                    map(track, now: context.date).frame(height: 300)
                } else {
                    ContentUnavailableView("Waiting for track layout", systemImage: "map",
                        description: Text("The circuit outline appears after a complete timed lap is available. Driver locations require a backend with track support."))
                        .frame(minHeight: 220)
                }
                footer(now: context.date)
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

    // MARK: Map

    private func map(_ track: TrackLayout, now: Date) -> some View {
        GeometryReader { geometry in
            if let projection = track.projection(width: geometry.size.width, height: geometry.size.height) {
                let outline = Path { path in
                    for (index, point) in track.points.enumerated() {
                        if let mapped = projection.project(x: point.x, y: point.y) {
                            let position = CGPoint(x: mapped.x, y: mapped.y)
                            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                        }
                    }
                }
                ZStack {
                    // Track surface: a wide dark kerb outline with a lighter strip inside it.
                    outline.stroke(RacingStyle.trackEdge, style: StrokeStyle(lineWidth: kerbWidth, lineCap: .round, lineJoin: .round))
                    outline.stroke(RacingStyle.trackSurface, style: StrokeStyle(lineWidth: surfaceWidth, lineCap: .round, lineJoin: .round))
                    startFinish(track, projection)
                    ForEach(snapshot.drivers) { driver in
                        if let location = driver.location,
                           let point = projection.project(x: location.x, y: location.y) {
                            marker(driver, location, at: point, now: now)
                        }
                    }
                    selectedLabel(projection, size: geometry.size, now: now)
                }
                .clipped()
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Track map. \(track.source)")
            } else {
                ContentUnavailableView("Track layout unavailable", systemImage: "map")
            }
        }
    }

    /// A chequered tick across the track at the first point of the lap, turned to face the direction of travel.
    @ViewBuilder private func startFinish(_ track: TrackLayout, _ projection: TrackProjection) -> some View {
        let mapped = track.points.compactMap { projection.project(x: $0.x, y: $0.y) }
        if let start = mapped.first,
           let ahead = mapped.dropFirst().first(where: { hypot($0.x - start.x, $0.y - start.y) >= 6 }) {
            ChequeredTick()
                .rotationEffect(.radians(atan2(ahead.y - start.y, ahead.x - start.x)))
                .position(x: start.x, y: start.y)
                .accessibilityHidden(true)
        }
    }

    private func marker(_ driver: TimingDriver, _ location: DriverLocation, at point: TrackPoint, now: Date) -> some View {
        let stale = location.isStale(at: now)
        let selected = selectedDriver == driver.number
        return Button { selectedDriver = selected ? nil : driver.number } label: {
            Text(String(driver.number)).font(RacingStyle.Typography.label.monospacedDigit())
                .foregroundStyle(.white).frame(width: markerSize, height: markerSize)
                .background(Color.team(driver.color), in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: selected ? 3 : 1))
        }
        .buttonStyle(.plain)
        .opacity(stale ? 0.35 : selectedDriver == nil || selected ? 1 : 0.4)
        .position(x: point.x, y: point.y)
        .zIndex(selected ? 1 : 0)
        .accessibilityLabel("\(driver.name), car \(driver.number), \(stale ? "stale location" : "location received"), \(location.date)")
    }

    /// The selected driver's code, in a tag beside the marker that never covers it.
    @ViewBuilder private func selectedLabel(_ projection: TrackProjection, size: CGSize, now: Date) -> some View {
        if let driver = snapshot.drivers.first(where: { $0.number == selectedDriver }),
           let location = driver.location,
           let point = projection.project(x: location.x, y: location.y) {
            let frame = MarkerLabelPlacement.frame(
                markerX: point.x, markerY: point.y, markerRadius: markerSize / 2 + 2,
                labelWidth: labelWidth, labelHeight: labelHeight,
                bounds: .init(x: 0, y: 0, width: size.width, height: size.height))
            Text(driver.acronym).font(RacingStyle.Typography.label).tracking(1)
                .foregroundStyle(Color(RacingPalette.onStatus))
                .frame(width: labelWidth, height: labelHeight)
                .background(Color(RacingPalette.textPrimary), in: Capsule())
                .overlay(Capsule().stroke(Color.team(driver.color), lineWidth: 2))
                .opacity(location.isStale(at: now) ? 0.5 : 1)
                .position(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
                .zIndex(2)
                .accessibilityHidden(true)
        }
    }

    // MARK: Footer

    @ViewBuilder private func footer(now: Date) -> some View {
        if let driver = snapshot.drivers.first(where: { $0.number == selectedDriver }) {
            HStack(spacing: RacingStyle.Space.m) {
                RoundedRectangle(cornerRadius: RacingStyle.Radius.tag).fill(Color.team(driver.color)).frame(width: 4, height: 36)
                VStack(alignment: .leading, spacing: RacingStyle.Space.xs) {
                    Text(driver.acronym).font(RacingStyle.Typography.code)
                    Text("\(driver.name) · \(driver.team)").font(RacingStyle.Typography.caption)
                        .foregroundStyle(RacingStyle.textSecondary)
                }
                Spacer(minLength: RacingStyle.Space.s)
                VStack(alignment: .trailing, spacing: RacingStyle.Space.xs) {
                    Text(driver.position.map { "P\($0)" } ?? "—").font(RacingStyle.Typography.figure)
                    Text(driver.locationState(at: now).label(for: driver, at: now))
                        .font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
                }
            }
            .padding(RacingStyle.Space.m)
            .background(RacingStyle.raised, in: RoundedRectangle(cornerRadius: RacingStyle.Radius.row))
            .accessibilityElement(children: .combine)
        } else {
            Text(snapshot.locationSummary(at: now))
                .font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
        }
    }
}

/// Ten-by-twenty point chequered flag mark; the long side runs across the track once rotated.
private struct ChequeredTick: View {
    private let square: CGFloat = 5

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<4, id: \.self) { row in
                GridRow {
                    ForEach(0..<2, id: \.self) { column in
                        Rectangle().fill((row + column).isMultiple(of: 2) ? Color.white : Color.black)
                            .frame(width: square, height: square)
                    }
                }
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
