import SwiftUI

struct DashboardView: View {
    let store: TimingStore
    let feed: FeedStatus

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RacingStyle.Space.xl) {
                hero
                if let error = store.error {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(RacingStyle.Typography.body).foregroundStyle(Color(RacingPalette.statusStale))
                }
                if let snapshot = store.snapshot {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: RacingStyle.Space.xl) {
                            // Side by side the two cards are the same height, so no dead block sits under the shorter one.
                            timingBoard(snapshot, fillsHeight: true).frame(width: 500)
                            TrackMapView(snapshot: snapshot, connected: store.connected, fillsHeight: true).frame(minWidth: 380)
                        }
                        VStack(spacing: RacingStyle.Space.xl) {
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
            }
            .racingPagePadding()
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .background(RacingStyle.background)
    }

    /// The one session hero: circuit large, then session name and how fresh the timing is.
    private var hero: some View {
        VStack(alignment: .leading, spacing: RacingStyle.Space.xs) {
            Text(store.snapshot?.session?.circuit ?? "Ready for lights out")
                .font(RacingStyle.Typography.display).racingHeading()
                .accessibilityAddTraits(.isHeader)
            sessionName
            if let detail = feed.timingDetail {
                Text(detail).font(RacingStyle.Typography.caption).foregroundStyle(Color(RacingPalette.statusStale))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var sessionName: some View {
        Text(store.snapshot?.session?.name ?? "Waiting for session")
            .font(RacingStyle.Typography.headline).foregroundStyle(RacingStyle.textSecondary)
    }

    private func timingBoard(_ snapshot: TimingSnapshot, fillsHeight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
            if snapshot.drivers.isEmpty {
                Text("Waiting for driver data…").font(RacingStyle.Typography.body).foregroundStyle(RacingStyle.textSecondary)
            }
            TimingTower(drivers: snapshot.drivers, showsGap: snapshot.drivers.hasUsableGaps)
        }
        .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
        .racingCard()
    }

    private func raceControl(_ snapshot: TimingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: RacingStyle.Space.m) {
            RacingSectionTitle(title: "Race control")
            if snapshot.messages.isEmpty {
                Text("No race-control messages yet.").font(RacingStyle.Typography.body).foregroundStyle(RacingStyle.textSecondary)
            }
            ForEach(snapshot.messages.prefix(10)) { message in
                raceControlRow(message)
            }
        }.racingCard()
    }

    @ScaledMetric(relativeTo: .body) private var iconWidth = 22

    // Flag categories can distinguish identical symbols (yellow/double yellow, SC/VSC).
    @ViewBuilder private func flagLabel(_ kind: RaceControlKind) -> some View {
        if kind != .info {
            Text(kind.label).racingLabel().foregroundStyle(kind.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func time(_ message: RaceMessage) -> some View {
        if let time = message.timestamp {
            Text(time.formatted(date: .omitted, time: .standard))
                .font(RacingStyle.Typography.caption.monospacedDigit()).foregroundStyle(RacingStyle.textSecondary)
                .lineLimit(1).fixedSize()
        }
    }

    private func raceControlRow(_ message: RaceMessage) -> some View {
        let kind = message.kind
        return HStack(alignment: .top, spacing: RacingStyle.Space.m) {
            Image(systemName: kind.symbol).foregroundStyle(kind.color)
                .frame(width: iconWidth).padding(.top, RacingStyle.Space.xs / 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RacingStyle.Space.xs) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: RacingStyle.Space.s) { flagLabel(kind); time(message) }
                    VStack(alignment: .leading, spacing: RacingStyle.Space.xs) { flagLabel(kind); time(message) }
                }
                Text(message.message).font(RacingStyle.Typography.body).foregroundStyle(RacingStyle.textPrimary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(RacingStyle.Space.m)
        .background(RacingStyle.raised, in: RoundedRectangle(cornerRadius: RacingStyle.Radius.row))
        .overlay(alignment: .leading) {
            if kind.severity >= .caution { Rectangle().fill(kind.color).frame(width: 3) }
        }
        .clipShape(RoundedRectangle(cornerRadius: RacingStyle.Radius.row))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message.accessibilitySummary(
            timeText: message.timestamp?.formatted(date: .omitted, time: .standard)))
    }
}
