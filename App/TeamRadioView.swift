import SwiftUI

/// The team-radio feed in the style of the broadcast graphic: a dark panel per message with the driver's
/// team colour, number and code, a TEAM RADIO tag, and a waveform strip that fills as the clip plays.
struct TeamRadioFeed: View {
    let snapshot: TimingSnapshot
    let connected: Bool
    let player: TeamRadioPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
            RacingSectionTitle(title: "Team radio", subtitle: snapshot.radioStatus(connected: connected, now: Date()))
            if snapshot.radios.isEmpty {
                Text("No team radio yet.").font(RacingStyle.Typography.body).foregroundStyle(RacingStyle.textSecondary)
            }
            // Every clip of the session, newest first; rows build lazily.
            LazyVStack(alignment: .leading, spacing: RacingStyle.Space.m) {
                ForEach(snapshot.radios) { radio in
                TeamRadioRow(radio: radio, driver: snapshot.driver(for: radio), player: player)
                }
            }
        }
        .racingCard()
        .onDisappear { player.stop() }
    }
}

private struct TeamRadioRow: View {
    let radio: TeamRadio
    let driver: TimingDriver?
    let player: TeamRadioPlayer
    @ScaledMetric(relativeTo: .body) private var buttonSize = 44
    @Environment(\.dynamicTypeSize) private var typeSize

    private var playing: Bool { player.playingID == radio.id }
    private var teamColor: Color { driver.map { Color.team($0.color) } ?? RacingStyle.textTertiary }
    private var timeText: String? { radio.timestamp?.formatted(date: .omitted, time: .standard) }

    var body: some View {
        HStack(spacing: RacingStyle.Space.m) {
            Rectangle().fill(teamColor).frame(width: 4)
            VStack(alignment: .leading, spacing: RacingStyle.Space.s) {
                header
                if !typeSize.isAccessibilitySize { waveform }
                if player.failedID == radio.id {
                    Label("Could not load this clip", systemImage: "exclamationmark.triangle.fill")
                        .font(RacingStyle.Typography.caption).foregroundStyle(Color(RacingPalette.statusStale))
                } else if radio.playbackURL == nil {
                    Text("Sample clip · no audio").font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
                }
            }
            .padding(.vertical, RacingStyle.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            playButton
        }
        .padding(.trailing, RacingStyle.Space.m)
        .background(RacingStyle.raised, in: RoundedRectangle(cornerRadius: RacingStyle.Radius.row))
        .clipShape(RoundedRectangle(cornerRadius: RacingStyle.Radius.row))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(radio.accessibilitySummary(driver: driver, timeText: timeText))
        .accessibilityValue(playing ? "Playing" : "")
        .accessibilityAddTraits(radio.playbackURL == nil ? [] : .isButton)
        .accessibilityAction(named: playing ? "Stop" : "Play") { player.toggle(radio) }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RacingStyle.Space.s) { tag; identity; Spacer(minLength: RacingStyle.Space.s); time }
            VStack(alignment: .leading, spacing: RacingStyle.Space.xs) { identity; HStack(spacing: RacingStyle.Space.s) { tag; time } }
        }
    }

    private var tag: some View {
        Label("Team radio", systemImage: "dot.radiowaves.left.and.right")
            .racingLabel().foregroundStyle(RacingStyle.textSecondary)
            .lineLimit(1).fixedSize()
    }

    private var identity: some View {
        HStack(spacing: RacingStyle.Space.s) {
            Text(driver?.acronym ?? "#\(radio.driverNumber)").font(RacingStyle.Typography.code).lineLimit(1).fixedSize()
            if let driver {
                Text("\(driver.number)").font(RacingStyle.Typography.data).foregroundStyle(RacingStyle.textSecondary).lineLimit(1)
                Text(driver.team).font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary).lineLimit(1)
            }
        }
    }

    @ViewBuilder private var time: some View {
        if let timeText {
            Text(timeText).font(RacingStyle.Typography.caption.monospacedDigit()).foregroundStyle(RacingStyle.textSecondary)
                .lineLimit(1).fixedSize()
        }
    }

    /// Decorative strip, filled left to right while the clip plays. It is not the clip's real loudness.
    private var waveform: some View {
        GeometryReader { proxy in
            let bars = TeamRadio.waveform(seed: radio.id, bars: max(Int(proxy.size.width / 5), 1))
            let filled = playing ? Int((player.progress * Double(bars.count)).rounded(.down)) : 0
            HStack(alignment: .center, spacing: 2) {
                ForEach(bars.indices, id: \.self) { index in
                    Capsule()
                        .fill(index < filled ? teamColor : RacingStyle.textTertiary.opacity(radio.playbackURL == nil ? 0.35 : 0.8))
                        .frame(width: 3, height: 24 * bars[index])
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .frame(height: 24)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var playButton: some View {
        if radio.playbackURL != nil {
            Button { player.toggle(radio) } label: {
                Image(systemName: playing ? "stop.fill" : "play.fill")
                    .frame(width: buttonSize, height: buttonSize)
                    .background(playing ? teamColor : RacingStyle.surface, in: Circle())
                    .foregroundStyle(playing ? RacingStyle.onRed : RacingStyle.textPrimary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityHidden(true)
        }
    }
}
