import SwiftUI

struct TrackMapView: View {
    let snapshot: TimingSnapshot
    let connected: Bool
    /// True beside the leaderboard: the card stretches to the row's height and the map fills what is left
    /// (the circuit keeps its own proportions, centred). Stacked, the map takes the circuit's own shape.
    var fillsHeight = false
    @State private var selectedDriver: Int?
    @State private var drawing: TrackDrawing?
    @State private var animationActive = false
    @State private var lastReceived = Date.distantPast
    @State private var motions: [Int: DriverMotion] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var markerSize = 28
    @ScaledMetric(relativeTo: .caption) private var labelWidth = 48
    @ScaledMetric(relativeTo: .caption) private var labelHeight = 22

    /// OpenF1's raw frame can face any way; this turns the circuit to its official map orientation.

    private let kerbWidth: CGFloat = 22
    private let surfaceWidth: CGFloat = 12

    var body: some View {
        // The card chrome (titles, picker, captions, track, footer) only needs the clock for its staleness
        // wording, so it follows a plain wall clock, once a second. Only the markers layer runs at the display rate.
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 1)) { context in
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
                if snapshot.mode != "demo", let track = snapshot.track {
                    Text(track.rotationDegrees == nil ? "Orientation unverified · Raw telemetry" : "Circuit orientation · MultiViewer")
                        .font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
                }
                footer(now: context.date)
            }
            .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
            .racingCard()
        }
        .task(id: snapshot.drivers.map(\.location)) {
            receivePositions()
            animationActive = connected && !reduceMotion
            do { try await Task.sleep(for: .seconds(MotionActivity.window)) } catch { return }
            // A newer position may have arrived while this timer was waking up: only the newest one decides.
            if !MotionActivity.isActive(lastReceived: lastReceived, now: Date()) { animationActive = false }
        }
        .onChange(of: connected) { motions = [:]; receivePositions() }
        .onChange(of: snapshot.session?.start) { selectedDriver = nil; motions = [:]; receivePositions() }
            }

    private func receivePositions() {
        let now = Date()
        lastReceived = now
        let numbers = Set(snapshot.drivers.map(\.number))
        motions = motions.filter { numbers.contains($0.key) }
        for driver in snapshot.drivers {
            guard let location = driver.location else {
                motions[driver.number] = nil
                continue
            }
            var motion = motions[driver.number] ?? DriverMotion()
            motion.receive(location, at: now, animated: connected && !reduceMotion)
            motions[driver.number] = motion
        }
    }

    /// The map takes the circuit's own shape (kept between 1:1 and 2:1) so it fills the card
    /// instead of floating in a fixed-height box.
    private func mapAspect(_ track: TrackLayout) -> CGFloat {
        CGFloat(min(max(track.aspectRatio ?? 1.5, 1.0), 2.0))
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
            let key = TrackDrawing.Key(track: track, size: geometry.size)
            // A cache miss is valid geometry, not an unavailable track.
            let currentDrawing = drawing.flatMap { $0.key == key ? $0 : nil } ?? TrackDrawing(key: key)
            Group {
            if let projection = currentDrawing.projection {
                let outline = currentDrawing.outline
                let notLive = snapshot.positionsNotLiveCaption(at: now, connected: connected)
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
                    startFinish(currentDrawing)
                    // Stale positions are one old spot: with every position stale nothing is plotted.
                    if notLive == nil {
                        MarkerLayer(
                            drivers: snapshot.drivers, motions: motions, projection: projection, size: geometry.size,
                            selectedDriver: selectedDriver, connected: connected, reduceMotion: reduceMotion,
                            animating: animationActive, markerSize: markerSize, labelWidth: labelWidth, labelHeight: labelHeight,
                            select: { selectedDriver = $0 })
                        accessibilityMarkers(projection, size: geometry.size, now: now)
                    }
                    if let note = unmappedSectorsNote(flags, sectors) {
                        sectorsUnknownNote(note)
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
            .task(id: key) { drawing = TrackDrawing(key: key) }
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

    /// What to say when a flagged sector cannot be shown: the circuit's sectors cannot be placed on the outline
    /// at all, or race control named a sector the circuit's table does not have.
    private func unmappedSectorsNote(_ flags: FlagStatus, _ sectors: SectorRuns?) -> String? {
        guard !flags.sectors.isEmpty else { return nil }
        guard let sectors else { return "Sector positions are not available for this circuit" }
        let missing = sectors.unmapped(flags.sectors)
        guard !missing.isEmpty else { return nil }
        return "Sector \(missing.map(String.init).joined(separator: ", ")) position not available"
    }

    private func sectorsUnknownNote(_ text: String) -> some View {
        Text(text)
            .font(RacingStyle.Typography.caption).dynamicTypeSize(...DynamicTypeSize.xLarge)
            .foregroundStyle(RacingStyle.textSecondary)
            .padding(.horizontal, RacingStyle.Space.m).padding(.vertical, RacingStyle.Space.xs)
            .background(RacingStyle.background.opacity(0.85), in: Capsule())
            .accessibilityHidden(true)
    }

    /// The markers are drawn, not views, so VoiceOver gets one invisible element per driver. They sit where
    /// the marker is as of this once-a-second update; touches are handled by the markers layer itself.
    private func accessibilityMarkers(_ projection: TrackProjection, size: CGSize, now: Date) -> some View {
        let spots = MarkerLayout.spots(drivers: snapshot.drivers, motions: motions, projection: projection, now: now,
                                       connected: connected, animated: !reduceMotion, markerSize: Double(markerSize),
                                       width: Double(size.width), height: Double(size.height))
        return ForEach(snapshot.drivers) { driver in
            if let location = driver.location, let point = spots[driver.number] {
                let stale = location.isStale(at: now)
                Color.clear.frame(width: max(markerSize, 44), height: max(markerSize, 44))
                    .position(x: point.x, y: point.y)
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("\(driver.name), car \(driver.number), \(stale ? "stale location" : "location received"), \(location.date)")
                    .accessibilityAction { selectedDriver = selectedDriver == driver.number ? nil : driver.number }
            }
        }
    }

    /// A chequered tick across the track at the first point of the lap, turned to face the direction of travel.
    @ViewBuilder private func startFinish(_ drawing: TrackDrawing) -> some View {
        if let start = drawing.start, let angle = drawing.startAngle {
            ChequeredTick()
                .rotationEffect(.radians(angle))
                .position(x: start.x, y: start.y)
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

/// The only view that runs at the display rate. It draws every marker into one Canvas at its exact
/// fractional position (anti-aliased, so slow motion is smooth rather than stepping a whole pixel at a time),
/// so nothing else in the card is re-evaluated per frame.
private struct MarkerLayer: View {
    let drivers: [TimingDriver]
    let motions: [Int: DriverMotion]
    let projection: TrackProjection
    let size: CGSize
    let selectedDriver: Int?
    let connected: Bool
    let reduceMotion: Bool
    let animating: Bool
    let markerSize: CGFloat
    let labelWidth: CGFloat
    let labelHeight: CGFloat
    let select: (Int?) -> Void

    private static let labelID = "selected-label"

    var body: some View {
        // Display-rate frames while a position is easing, one a second otherwise. The timeline is rebuilt when that
        // changes: a running timeline keeps its old (up to one second) tick before it notices a new schedule.
        TimelineView(.animation(minimumInterval: animatesPerFrame ? nil : 1)) { context in
            let now = context.date
            Canvas { graphics, canvasSize in
                let spots = spots(at: now)
                for driver in drivers.sorted(by: drawingOrder) {
                    guard let location = driver.location, let point = spots[driver.number],
                          let symbol = graphics.resolveSymbol(id: driver.number) else { continue }
                    var layer = graphics
                    layer.opacity = location.isStale(at: now) ? 0.35 : selectedDriver == nil || selectedDriver == driver.number ? 1 : 0.4
                    layer.draw(symbol, at: CGPoint(x: point.x, y: point.y))
                }
                // The selected driver's code, in a tag beside the marker that never covers it.
                if let driver = drivers.first(where: { $0.number == selectedDriver }), let location = driver.location,
                   let point = spots[driver.number], let label = graphics.resolveSymbol(id: Self.labelID) {
                    let frame = MarkerLabelPlacement.frame(
                        markerX: point.x, markerY: point.y, markerRadius: markerSize / 2 + 2,
                        labelWidth: labelWidth, labelHeight: labelHeight,
                        bounds: .init(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height))
                    var layer = graphics
                    layer.opacity = location.isStale(at: now) ? 0.5 : 1
                    layer.draw(label, at: CGPoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2))
                }
            } symbols: {
                ForEach(drivers) { driver in marker(driver).tag(driver.number) }
                if let driver = drivers.first(where: { $0.number == selectedDriver }) { label(driver).tag(Self.labelID) }
            }
            .accessibilityHidden(true)
            .gesture(SpatialTapGesture().onEnded { tap in
                let hit = MarkerLayout.driver(at: TrackPoint(x: tap.location.x, y: tap.location.y),
                                              in: spots(at: Date()), radius: max(Double(markerSize), 44) / 2)
                if let hit { select(selectedDriver == hit ? nil : hit) }
            })
        }
        .id(animatesPerFrame)
    }

    private var animatesPerFrame: Bool { animating && connected && !reduceMotion }

    private func spots(at now: Date) -> [Int: TrackPoint] {
        MarkerLayout.spots(drivers: drivers, motions: motions, projection: projection, now: now,
                           connected: connected, animated: !reduceMotion, markerSize: Double(markerSize),
                           width: Double(size.width), height: Double(size.height))
    }

    /// Back to front: the selected driver's marker is drawn last, on top.
    private func drawingOrder(_ a: TimingDriver, _ b: TimingDriver) -> Bool {
        let (aSelected, bSelected) = (a.number == selectedDriver, b.number == selectedDriver)
        return aSelected == bSelected ? a.number < b.number : bSelected
    }

    private func marker(_ driver: TimingDriver) -> some View {
        let selected = selectedDriver == driver.number
        return Text(String(driver.number)).font(RacingStyle.Typography.label.monospacedDigit())
            .foregroundStyle(Color(RacingPalette.markerInk)).frame(width: markerSize, height: markerSize)
            .background(Color.team(driver.color), in: Circle())
            .overlay(Circle().stroke(Color(RacingPalette.markerInk), lineWidth: selected ? 3 : 1))
    }

    private func label(_ driver: TimingDriver) -> some View {
        Text(driver.acronym).font(RacingStyle.Typography.label).tracking(1)
            .foregroundStyle(Color(RacingPalette.onStatus))
            .frame(width: labelWidth, height: labelHeight)
            .background(Color(RacingPalette.textPrimary), in: Capsule())
            .overlay(Capsule().stroke(Color.team(driver.color), lineWidth: 2))
    }
}

/// Cached static geometry, rebuilt only when the circuit or viewport changes.
private struct TrackDrawing {
    struct Key: Equatable {
        let track: TrackLayout
        let size: CGSize
    }
    let key: Key
    let projection: TrackProjection?
    let outline: Path
    let start: TrackPoint?
    let startAngle: Double?

    init(key: Key) {
        self.key = key
        let projection = key.track.projection(width: key.size.width, height: key.size.height)
        self.projection = projection
        let mapped = key.track.points.compactMap { projection?.project(x: $0.x, y: $0.y) }
        outline = Path { path in
            for (index, point) in mapped.enumerated() {
                let position = CGPoint(x: point.x, y: point.y)
                if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
            }
        }
        start = mapped.first
        if let start = mapped.first,
           let ahead = mapped.dropFirst().first(where: { hypot($0.x - start.x, $0.y - start.y) >= 6 }) {
            startAngle = atan2(ahead.y - start.y, ahead.x - start.x)
        } else {
            startAngle = nil
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
