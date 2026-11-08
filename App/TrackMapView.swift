import SwiftUI

struct TrackMapView: View {
    let snapshot: TimingSnapshot
    let connected: Bool
    /// True beside the leaderboard: the card stretches to the row's height and the map fills what is left
    /// (the circuit keeps its own proportions, centred). Stacked, the map takes the circuit's own shape.
    var fillsHeight = false
    @State private var selectedDriver: Int?
    @ScaledMetric(relativeTo: .caption) private var markerSize = 28
    @ScaledMetric(relativeTo: .caption) private var labelWidth = 48
    @ScaledMetric(relativeTo: .caption) private var labelHeight = 22

    /// OpenF1's raw frame can face any way; this turns the circuit to its official map orientation.
    private var rotation: Double { CircuitOrientation.rotation(forCircuit: snapshot.session?.circuit) }

    private let kerbWidth: CGFloat = 22
    private let surfaceWidth: CGFloat = 12

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let notLive = snapshot.allPositionsStale(at: context.date)
            VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Label("Approximate positions", systemImage: "location")
                            .font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
                            .accessibilityLabel("Driver tracker. Approximate positions")
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        driverPicker(disabled: notLive)
                    }
                    VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
                        Label("Approximate positions", systemImage: "location")
                            .font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
                            .accessibilityLabel("Driver tracker. Approximate positions")
                            .accessibilityAddTraits(.isHeader)
                        driverPicker(disabled: notLive)
                    }
                }
                // When no position is live the map itself carries the caption, so the status line stays quiet.
                if !notLive {
                    Text(snapshot.trackStatus(at: context.date, connected: connected))
                        .font(RacingStyle.Typography.label)
                        .foregroundStyle(snapshot.mode == "demo" ? Color(RacingPalette.statusDemo) : RacingStyle.textSecondary)
                }
                if let track = snapshot.track {
                    if fillsHeight {
                        map(track, now: context.date)
                            .frame(maxWidth: .infinity, minHeight: 280, maxHeight: .infinity)
                    } else {
                        map(track, now: context.date)
                            .aspectRatio(mapAspect(track), contentMode: .fit)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    ContentUnavailableView("Waiting for track layout", systemImage: "map",
                        description: Text("The circuit outline appears after a complete timed lap is available. Driver locations require a backend with track support."))
                        .frame(minHeight: 220)
                }
                footer(now: context.date)
            }
            .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
            .racingCard()
        }
        .onChange(of: snapshot.session?.start) { selectedDriver = nil }
            }

    /// The map takes the circuit's own shape (kept between 1:1 and 2:1) so it fills the card
    /// instead of floating in a fixed-height box.
    private func mapAspect(_ track: TrackLayout) -> CGFloat {
        CGFloat(min(max(track.aspectRatio(rotationDegrees: rotation) ?? 1.5, 1.0), 2.0))
    }

    private func driverPicker(disabled: Bool) -> some View {
        Picker("Follow driver", selection: $selectedDriver) {
            Text("All drivers").tag(Int?.none)
            ForEach(snapshot.drivers) { driver in
                Text("\(driver.number) · \(driver.acronym)").tag(Optional(driver.number))
            }
        }.labelsHidden().fixedSize()
            // Nothing to follow when no position is live.
            .disabled(disabled)
    }

    // MARK: Map

    private func map(_ track: TrackLayout, now: Date) -> some View {
        GeometryReader { geometry in
            if let projection = track.projection(width: geometry.size.width, height: geometry.size.height, rotationDegrees: rotation) {
                let outline = Path { path in
                    for (index, point) in track.points.enumerated() {
                        if let mapped = projection.project(x: point.x, y: point.y) {
                            let position = CGPoint(x: mapped.x, y: mapped.y)
                            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                        }
                    }
                }
                let notLive = snapshot.positionsNotLiveCaption(at: now, connected: connected)
                // Stale positions are one old spot: with every position stale nothing is plotted.
                let spots = notLive == nil ? markerSpots(projection, size: geometry.size) : [:]
                let flags = snapshot.activeFlags(at: now)
                // Flags from a feed that is not live are the last known state, so they are drawn fainter.
                let flagOpacity = FeedStatus.resolve(snapshot: snapshot, connected: connected, hasError: false, now: now).kind == .live ? 1.0 : 0.5
                let sectors = flags.sectors.isEmpty ? nil : track.sectorRuns(circuit: snapshot.session?.circuit, isDemo: snapshot.mode == "demo")
                ZStack {
                    // Track surface: a wide dark kerb outline with a lighter strip inside it.
                    outline.stroke(RacingStyle.trackEdge, style: StrokeStyle(lineWidth: kerbWidth, lineCap: .round, lineJoin: .round))
                    outline.stroke(RacingStyle.trackSurface, style: StrokeStyle(lineWidth: surfaceWidth, lineCap: .round, lineJoin: .round))
                    trackFlagOverlay(outline, flags.track, opacity: flagOpacity)
                    sectorFlagOverlay(flags, sectors, projection, opacity: flagOpacity)
                    startFinish(track, projection)
                    ForEach(snapshot.drivers) { driver in
                        if let location = driver.location, let point = spots[driver.number] {
                            marker(driver, location, at: point, now: now)
                        }
                    }
                    selectedLabel(spots, size: geometry.size, now: now)
                    if !flags.sectors.isEmpty, sectors == nil {
                        sectorsUnknownNote(flags)
                            .position(x: geometry.size.width / 2, y: geometry.size.height - 18)
                    }
                    if let notLive {
                        // Capped like other chrome: a caption that grows with the text would cover the whole map.
                        Text(notLive).font(RacingStyle.Typography.bodyStrong)
                            .dynamicTypeSize(...DynamicTypeSize.xLarge)
                            .foregroundStyle(RacingStyle.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, RacingStyle.Space.l).padding(.vertical, RacingStyle.Space.s)
                            .background(RacingStyle.background.opacity(0.85), in: Capsule())
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                            .accessibilityLabel(notLive)
                    }
                }
                .clipped()
                .accessibilityElement(children: .contain)
                .accessibilityLabel(["Track map. \(track.source)", flags.isClear ? nil : flags.spokenDescription].compactMap { $0 }.joined(separator: ". "))
            } else {
                ContentUnavailableView("Track layout unavailable", systemImage: "map")
            }
        }
    }

    // MARK: Flags

    private func path(_ run: [TrackPoint], _ projection: TrackProjection) -> Path {
        Path { path in
            for (index, point) in run.compactMap({ projection.project(x: $0.x, y: $0.y) }).enumerated() {
                let position = CGPoint(x: point.x, y: point.y)
                if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
            }
        }
    }

    /// Red flag, safety car and virtual safety car cover the whole circuit: the track surface takes the
    /// flag's colour, and the virtual safety car is dashed so it differs from the full safety car without colour.
    @ViewBuilder private func trackFlagOverlay(_ outline: Path, _ flag: TrackFlag, opacity: Double) -> some View {
        if flag != .clear {
            let dashed = flag == .virtualSafetyCar
            // A glow in the kerb, because red and orange alone sit too close to the grey surface.
            outline.stroke(flag.kind.color.opacity(0.35 * opacity), style: StrokeStyle(lineWidth: kerbWidth, lineCap: .round, lineJoin: .round))
            outline.stroke(flag.kind.color.opacity(opacity),
                           style: StrokeStyle(lineWidth: surfaceWidth, lineCap: dashed ? .butt : .round, lineJoin: .round,
                                              dash: dashed ? [12, 8] : []))
        }
    }

    /// Each yellow sector lights up its own stretch of the track with its number. A double yellow also gets a
    /// dark dashed stripe, so the two are told apart without colour.
    @ViewBuilder private func sectorFlagOverlay(_ flags: FlagStatus, _ sectors: SectorRuns?, _ projection: TrackProjection, opacity: Double) -> some View {
        if let sectors {
            let yellow = Color(RacingPalette.flagYellow)
            ForEach(flags.sectors) { sector in
                let pieces = sectors.points(forSector: sector.sector)
                ForEach(pieces.indices, id: \.self) { index in
                    let stretch = path(pieces[index], projection)
                    stretch.stroke(yellow.opacity(0.3 * opacity), style: StrokeStyle(lineWidth: kerbWidth, lineCap: .butt, lineJoin: .round))
                    stretch.stroke(yellow.opacity(opacity), style: StrokeStyle(lineWidth: surfaceWidth, lineCap: .butt, lineJoin: .round))
                    if sector.flag == .doubleYellow {
                        stretch.stroke(RacingStyle.trackEdge.opacity(opacity), style: StrokeStyle(lineWidth: 4, lineCap: .butt, lineJoin: .round, dash: [6, 6]))
                    }
                }
                if let middle = longestPiece(pieces).flatMap({ $0[$0.count / 2] }).flatMap({ projection.project(x: $0.x, y: $0.y) }) {
                    sectorBadge(sector, opacity: opacity).position(x: middle.x, y: middle.y)
                }
            }
        }
    }

    private func longestPiece(_ pieces: [[TrackPoint]]) -> [TrackPoint]? {
        pieces.max { $0.count < $1.count }
    }

    private func sectorBadge(_ sector: SectorFlag, opacity: Double) -> some View {
        Text(String(sector.sector)).font(RacingStyle.Typography.label.monospacedDigit())
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .foregroundStyle(Color(RacingPalette.onStatus))
            .padding(.horizontal, RacingStyle.Space.xs + 2).padding(.vertical, 1)
            .background(Color(RacingPalette.flagYellow).opacity(opacity), in: Capsule())
            .overlay(Capsule().stroke(Color(RacingPalette.onStatus), lineWidth: sector.flag == .doubleYellow ? 2 : 1))
            .accessibilityHidden(true)
    }

    /// Shown when a sector is flagged but this circuit's sectors cannot be placed on the outline.
    private func sectorsUnknownNote(_ flags: FlagStatus) -> some View {
        Text("Sector positions are not available for this circuit")
            .font(RacingStyle.Typography.caption).dynamicTypeSize(...DynamicTypeSize.xLarge)
            .foregroundStyle(RacingStyle.textSecondary)
            .padding(.horizontal, RacingStyle.Space.m).padding(.vertical, RacingStyle.Space.xs)
            .background(RacingStyle.background.opacity(0.85), in: Capsule())
            .accessibilityHidden(true)
    }

    /// Where each located driver's marker is drawn: the projected position, nudged apart in
    /// timing order when markers would overlap.
    private func markerSpots(_ projection: TrackProjection, size: CGSize) -> [Int: TrackPoint] {
        let located = snapshot.drivers.compactMap { driver -> (Int, TrackPoint)? in
            guard let location = driver.location, let point = projection.project(x: location.x, y: location.y) else { return nil }
            return (driver.number, point)
        }
        let radius = Double(markerSize) / 2
        let bounds = MarkerLabelPlacement.Rect(x: radius, y: radius, width: max(0, Double(size.width) - 2 * radius),
                                               height: max(0, Double(size.height) - 2 * radius))
        let spread = MarkerSpread.separated(located.map(\.1), minDistance: Double(markerSize) * 0.95, bounds: bounds)
        return Dictionary(uniqueKeysWithValues: zip(located.map(\.0), spread))
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
                .foregroundStyle(Color(RacingPalette.markerInk)).frame(width: markerSize, height: markerSize)
                .background(Color.team(driver.color), in: Circle())
                .overlay(Circle().stroke(Color(RacingPalette.markerInk), lineWidth: selected ? 3 : 1))
        }
        .buttonStyle(.plain)
        .opacity(stale ? 0.35 : selectedDriver == nil || selected ? 1 : 0.4)
        .position(x: point.x, y: point.y)
        .zIndex(selected ? 1 : 0)
        .accessibilityLabel("\(driver.name), car \(driver.number), \(stale ? "stale location" : "location received"), \(location.date)")
    }

    /// The selected driver's code, in a tag beside the marker that never covers it.
    @ViewBuilder private func selectedLabel(_ spots: [Int: TrackPoint], size: CGSize, now: Date) -> some View {
        if let driver = snapshot.drivers.first(where: { $0.number == selectedDriver }),
           let location = driver.location,
           let point = spots[driver.number] {
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
        if let driver = snapshot.drivers.first(where: { $0.number == selectedDriver }), !snapshot.allPositionsStale(at: now) {
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
        } else if snapshot.allPositionsStale(at: now), let age = snapshot.newestPositionAge(at: now) {
            Text("Newest position received \(DurationText.compact(seconds: age)) ago")
                .font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
        } else {
            Label(snapshot.locationSummary(at: now), systemImage: "location.circle")
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
                        Rectangle().fill((row + column).isMultiple(of: 2) ? Color(RacingPalette.chequeredLight) : Color(RacingPalette.chequeredDark))
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
