import SwiftUI

/// What is flagged on the circuit right now, shown above every page so a red flag, a safety car or a
/// yellow sector is never one swipe away. Each line says it in words and a symbol as well as colour.
/// Nothing is drawn while the track is clear.
struct FlagBanner: View {
    let snapshot: TimingSnapshot?
    let feed: FeedStatus
    let now: Date
    @ScaledMetric(relativeTo: .body) private var iconWidth = 22

    var body: some View {
        let flags = snapshot?.activeFlags(at: now) ?? .clear
        if !flags.isClear {
            VStack(alignment: .leading, spacing: RacingStyle.Space.s) {
                // Side by side when they fit, which keeps the banner to one row on a wide screen.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: RacingStyle.Space.l) { lines(flags) }
                    VStack(alignment: .leading, spacing: RacingStyle.Space.s) { lines(flags) }
                }
                if let caveat = caveat {
                    Text(caveat).font(RacingStyle.Typography.caption)
                        .foregroundStyle(Color(feed.isDemo ? RacingPalette.statusDemo : RacingPalette.statusStale))
                }
            }
            .padding(RacingStyle.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RacingStyle.raised, in: RoundedRectangle(cornerRadius: RacingStyle.Radius.row))
            .overlay(alignment: .leading) { Rectangle().fill(accent(flags)).frame(width: 4) }
            .clipShape(RoundedRectangle(cornerRadius: RacingStyle.Radius.row))
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
            .racingPagePadding(.horizontal)
            .padding(.top, RacingStyle.Space.m)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Flags")
            .accessibilityValue([flags.spokenDescription, caveat].compactMap { $0 }.joined(separator: " "))
        }
    }

    @ViewBuilder private func lines(_ flags: FlagStatus) -> some View {
        ForEach(Array(flags.lines.enumerated()), id: \.offset) { _, line in
            HStack(alignment: .firstTextBaseline, spacing: RacingStyle.Space.s) {
                Image(systemName: line.kind.symbol).foregroundStyle(line.kind.color)
                    .frame(width: iconWidth).accessibilityHidden(true)
                Text(line.text).font(RacingStyle.Typography.bodyStrong).foregroundStyle(RacingStyle.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Flags are only as current as the feed: demo ones are simulated, and a feed that has stopped means
    /// they are the last known state.
    private var caveat: String? {
        if feed.isDemo { return "Demo · simulated flags" }
        switch feed.kind {
        case .live: return nil
        case .stale, .offline, .connecting:
            return "Last known · timing is \(feed.label.lowercased())" + (feed.ageText.map { ", \($0) old" } ?? "")
        }
    }

    /// The bar takes the most urgent line's colour.
    private func accent(_ flags: FlagStatus) -> Color {
        flags.lines.first?.kind.color ?? RacingStyle.textSecondary
    }
}
