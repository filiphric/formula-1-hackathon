import SwiftUI

/// The leaderboard as a timing tower: position, team tag, driver code, a timing column, LAST LAP, tyre.
/// Where a race reports gaps, tapping anywhere on the tower steps the timing column through the gap
/// to the car ahead, the gap to the leader and each driver's fastest lap.
/// It tries the widest column set first and drops team, then last lap, before it ever scrolls.
/// Sessions without gaps drop GAP, keep LAST LAP at every width, and give the room GAP leaves to the
/// team name (truncating), which only the narrowest layout drops.
struct TimingTower: View {
    let drivers: [TimingDriver]
    /// False in sessions that report no gaps (practice, qualifying): the GAP column would be all dashes.
    let showsGap: Bool
    @ScaledMetric(relativeTo: .body) private var rowHeight = 44
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var metric: TimingMetric = .interval

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize { stackedTower } else { gridTower }
        }
        // The whole tower is the target, not just the timing column, so a thumb anywhere works.
        .contentShape(Rectangle())
        .onTapGesture(perform: cycleMetric)
    }

    /// Without a gap column (practice, qualifying) there is nothing to switch.
    private func cycleMetric() {
        guard showsGap else { return }
        metric = metric.next
        AccessibilityNotification.Announcement("Showing \(metric.spokenName)").post()
    }

    /// At accessibility text sizes no column set fits a phone, so each driver becomes two lines:
    /// position, code and tyre; then gap and last lap. Nothing scrolls sideways.
    private var stackedTower: some View {
        VStack(alignment: .leading, spacing: 0) {
            // No header row at this size, so say which timing the second line shows.
            if showsGap {
                Text(metric.title).racingLabel().foregroundStyle(RacingStyle.textSecondary)
                    .padding(.bottom, RacingStyle.Space.s)
                    .accessibilityHidden(true)
            }
            ForEach(drivers) { driver in
                VStack(alignment: .leading, spacing: RacingStyle.Space.s) {
                    HStack(spacing: RacingStyle.Space.m) {
                        Text(driver.position.map(String.init) ?? "—").font(RacingStyle.Typography.figure).lineLimit(1)
                        RoundedRectangle(cornerRadius: RacingStyle.Radius.tag).fill(Color.team(driver.color))
                            .frame(width: 4, height: rowHeight * 0.6)
                        Text(driver.acronym).font(RacingStyle.Typography.code).lineLimit(1)
                        Spacer(minLength: RacingStyle.Space.s)
                        TyreBadge(compound: TyreCompound(driver.compound))
                    }
                    HStack(spacing: RacingStyle.Space.m) {
                        if showsGap { timing(driver) }
                        Spacer(minLength: RacingStyle.Space.s)
                        lastLap(driver, hasTimingColumn: showsGap)
                    }
                }
                .padding(.vertical, RacingStyle.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(driver.accessibilitySummary(showingGap: showsGap, metric: metric))
                .accessibilityActions { switchAction }
                if driver.id != drivers.last?.id { Divider().overlay(RacingStyle.raised) }
            }
        }
    }

    private var gridTower: some View {
        ViewThatFits(in: .horizontal) {
            tower(.wide)
            tower(.standard)
            tower(.compact)
            // Last resort: even the compact tower does not fit (huge text on a narrow screen).
            ScrollView(.horizontal) { tower(.compact) }
        }
    }

    private func tower(_ layout: TimingLayout) -> some View {
        let columns = layout.columns(showingGap: showsGap)
        return Grid(alignment: .leading, horizontalSpacing: RacingStyle.Space.m, verticalSpacing: 0) {
            GridRow {
                Image(systemName: "number").accessibilityLabel("Position").help("Position").gridColumnAlignment(.trailing)
                Color.clear.frame(width: 4, height: 1)
                Image(systemName: "person.fill").accessibilityLabel("Driver").help("Driver").gridColumnAlignment(.leading)
                if columns.contains(.team) { Image(systemName: "person.2.fill").accessibilityLabel("Team").help("Team").gridColumnAlignment(.leading) }
                if columns.contains(.gap) { Text(metric.title).gridColumnAlignment(.trailing) }
                if columns.contains(.lastLap) { Text("Last lap").gridColumnAlignment(.trailing) }
                Image(systemName: "circle.circle").accessibilityLabel("Tyre").help("Tyre").gridColumnAlignment(.center)
            }
            .racingLabel().foregroundStyle(RacingStyle.textSecondary)
            .lineLimit(1).fixedSize()
            .frame(minHeight: 28)
            .accessibilityHidden(true)
            Divider().overlay(RacingStyle.raised).gridCellUnsizedAxes(.horizontal)
            ForEach(drivers) { driver in
                row(driver, layout, columns)
                if driver.id != drivers.last?.id {
                    Divider().overlay(RacingStyle.raised).gridCellUnsizedAxes(.horizontal)
                }
            }
        }
    }

    private func row(_ driver: TimingDriver, _ layout: TimingLayout, _ columns: [TimingColumn]) -> some View {
        GridRow {
            Text(driver.position.map(String.init) ?? "—")
                .font(RacingStyle.Typography.figure)
                .lineLimit(1).fixedSize()
                .frame(minHeight: rowHeight)
            RoundedRectangle(cornerRadius: RacingStyle.Radius.tag).fill(Color.team(driver.color))
                .frame(width: 4, height: rowHeight * 0.6)
            Text(driver.acronym).font(RacingStyle.Typography.code)
                .lineLimit(1).fixedSize()
                .frame(maxWidth: columns.contains(.team) ? nil : .infinity, alignment: .leading)
            if columns.contains(.team) {
                Text(driver.team).font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
                    .lineLimit(1).truncationMode(.tail)
                    // Wide wants the whole name. Below that the name asks for little and truncates, so
                    // this layout is chosen whenever a short team name fits.
                    .frame(minWidth: 0, idealWidth: layout.showsFullTeamName ? nil : 48, maxWidth: .infinity, alignment: .leading)
            }
            if columns.contains(.gap) { timing(driver) }
            if columns.contains(.lastLap) { lastLap(driver, hasTimingColumn: columns.contains(.gap)) }
            TyreBadge(compound: TyreCompound(driver.compound))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(driver.accessibilitySummary(showingGap: columns.contains(.gap), metric: metric))
        .accessibilityActions { switchAction }
    }

    /// VoiceOver cannot discover a tap on the tower, so each row offers it as an action, but only
    /// where there is something to switch.
    @ViewBuilder private var switchAction: some View {
        if showsGap { Button("Show \(metric.next.spokenName)", action: cycleMetric) }
    }

    /// The last lap time. A car in the pits shows the PIT chip in the timing column; without one (practice,
    /// qualifying) the chip takes the last lap's place instead, so it is never hidden.
    @ViewBuilder private func lastLap(_ driver: TimingDriver, hasTimingColumn: Bool) -> some View {
        if driver.isInPit && !hasTimingColumn {
            PitChip()
        } else {
            Text(driver.formattedLap).font(RacingStyle.Typography.data).foregroundStyle(RacingStyle.textSecondary)
                .lineLimit(1).fixedSize()
        }
    }

    @ViewBuilder private func timing(_ driver: TimingDriver) -> some View {
        if driver.isInPit {
            PitChip()
        } else if driver.isLeader && metric.marksLeader {
            // A filled brand-red chip, so the leader is a shape and not only a word.
            Image(systemName: "crown.fill").font(RacingStyle.Typography.label).accessibilityLabel("Leader").help("Leader")
                .lineLimit(1).fixedSize()
                .foregroundStyle(RacingStyle.onRed)
                .padding(.horizontal, RacingStyle.Space.s).padding(.vertical, RacingStyle.Space.xs)
                .background(RacingStyle.red, in: Capsule())
        } else {
            Text(driver.timingText(metric)).font(RacingStyle.Typography.data).lineLimit(1).fixedSize()
        }
    }
}
