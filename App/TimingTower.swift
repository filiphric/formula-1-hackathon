import SwiftUI

/// The leaderboard as a timing tower: position, team tag, driver code, GAP, LAST LAP, tyre.
/// It tries the widest column set first and drops team, then last lap, before it ever scrolls.
struct TimingTower: View {
    let drivers: [TimingDriver]
    @ScaledMetric(relativeTo: .body) private var rowHeight = 44

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tower(.wide)
            tower(.standard)
            tower(.compact)
            // Last resort: even the compact tower does not fit (huge text on a narrow screen).
            ScrollView(.horizontal) { tower(.compact) }
        }
    }

    private func tower(_ layout: TimingLayout) -> some View {
        Grid(alignment: .leading, horizontalSpacing: RacingStyle.Space.m, verticalSpacing: 0) {
            GridRow {
                Text("Pos").gridColumnAlignment(.trailing)
                Color.clear.frame(width: 4, height: 1)
                Text("Driver").gridColumnAlignment(.leading)
                if layout.shows(.team) { Text("Team").gridColumnAlignment(.leading) }
                Text("Gap").gridColumnAlignment(.trailing)
                if layout.shows(.lastLap) { Text("Last lap").gridColumnAlignment(.trailing) }
                Text("Tyre").gridColumnAlignment(.center)
            }
            .racingLabel().foregroundStyle(RacingStyle.textSecondary)
            .frame(minHeight: 28)
            .accessibilityHidden(true)
            Divider().overlay(RacingStyle.raised).gridCellUnsizedAxes(.horizontal)
            ForEach(drivers) { driver in
                row(driver, layout)
                if driver.id != drivers.last?.id {
                    Divider().overlay(RacingStyle.raised).gridCellUnsizedAxes(.horizontal)
                }
            }
        }
    }

    private func row(_ driver: TimingDriver, _ layout: TimingLayout) -> some View {
        GridRow {
            Text(driver.position.map(String.init) ?? "—")
                .font(RacingStyle.Typography.figure)
                .frame(minHeight: rowHeight)
            RoundedRectangle(cornerRadius: 2).fill(Color.team(driver.color))
                .frame(width: 4, height: rowHeight * 0.6)
            Text(driver.acronym).font(RacingStyle.Typography.code)
                .frame(maxWidth: layout.shows(.team) ? nil : .infinity, alignment: .leading)
            if layout.shows(.team) {
                Text(driver.team).font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }
            gap(driver)
            if layout.shows(.lastLap) {
                Text(driver.formattedLap).font(RacingStyle.Typography.data).foregroundStyle(RacingStyle.textSecondary)
            }
            TyreBadge(compound: TyreCompound(driver.compound))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(driver.accessibilitySummary)
    }

    @ViewBuilder private func gap(_ driver: TimingDriver) -> some View {
        if driver.isLeader {
            // A filled brand-red chip, so the leader is a shape and not only a word.
            Text("LEADER").font(RacingStyle.Typography.label).tracking(1)
                .foregroundStyle(RacingStyle.onRed)
                .padding(.horizontal, RacingStyle.Space.s).padding(.vertical, RacingStyle.Space.xs)
                .background(RacingStyle.red, in: Capsule())
        } else {
            Text(driver.gapText).font(RacingStyle.Typography.data)
        }
    }
}
