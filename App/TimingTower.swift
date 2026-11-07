import SwiftUI

/// The leaderboard as a timing tower: position, team tag, driver code, GAP, LAST LAP, tyre.
/// It tries the widest column set first and drops team, then last lap, before it ever scrolls.
/// Sessions without gaps drop GAP and keep LAST LAP at every width.
struct TimingTower: View {
    let drivers: [TimingDriver]
    /// False in sessions that report no gaps (practice, qualifying): the GAP column would be all dashes.
    let showsGap: Bool
    @ScaledMetric(relativeTo: .body) private var rowHeight = 44
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize { stackedTower } else { gridTower }
    }

    /// At accessibility text sizes no column set fits a phone, so each driver becomes two lines:
    /// position, code and tyre; then gap and last lap. Nothing scrolls sideways.
    private var stackedTower: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                        if showsGap { gap(driver) }
                        Spacer(minLength: RacingStyle.Space.s)
                        Text(driver.formattedLap).font(RacingStyle.Typography.data).foregroundStyle(RacingStyle.textSecondary).lineLimit(1)
                    }
                }
                .padding(.vertical, RacingStyle.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(driver.accessibilitySummary(showingGap: showsGap))
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
                Text("Pos").gridColumnAlignment(.trailing)
                Color.clear.frame(width: 4, height: 1)
                Text("Driver").gridColumnAlignment(.leading)
                if columns.contains(.team) { Text("Team").gridColumnAlignment(.leading) }
                if columns.contains(.gap) { Text("Gap").gridColumnAlignment(.trailing) }
                if columns.contains(.lastLap) { Text("Last lap").gridColumnAlignment(.trailing) }
                Text("Tyre").gridColumnAlignment(.center)
            }
            .racingLabel().foregroundStyle(RacingStyle.textSecondary)
            .lineLimit(1).fixedSize()
            .frame(minHeight: 28)
            .accessibilityHidden(true)
            Divider().overlay(RacingStyle.raised).gridCellUnsizedAxes(.horizontal)
            ForEach(drivers) { driver in
                row(driver, columns)
                if driver.id != drivers.last?.id {
                    Divider().overlay(RacingStyle.raised).gridCellUnsizedAxes(.horizontal)
                }
            }
        }
    }

    private func row(_ driver: TimingDriver, _ columns: [TimingColumn]) -> some View {
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
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }
            if columns.contains(.gap) { gap(driver) }
            if columns.contains(.lastLap) {
                Text(driver.formattedLap).font(RacingStyle.Typography.data).foregroundStyle(RacingStyle.textSecondary)
                    .lineLimit(1).fixedSize()
            }
            TyreBadge(compound: TyreCompound(driver.compound))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(driver.accessibilitySummary(showingGap: columns.contains(.gap)))
    }

    @ViewBuilder private func gap(_ driver: TimingDriver) -> some View {
        if driver.isLeader {
            // A filled brand-red chip, so the leader is a shape and not only a word.
            Text("LEADER").font(RacingStyle.Typography.label).tracking(1)
                .lineLimit(1).fixedSize()
                .foregroundStyle(RacingStyle.onRed)
                .padding(.horizontal, RacingStyle.Space.s).padding(.vertical, RacingStyle.Space.xs)
                .background(RacingStyle.red, in: Capsule())
        } else {
            Text(driver.gapText).font(RacingStyle.Typography.data).lineLimit(1).fixedSize()
        }
    }
}
