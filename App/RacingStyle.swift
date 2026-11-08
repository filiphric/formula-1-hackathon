import SwiftUI

/// Shared visual language for the race centre and calendar.
extension Color {
    init(_ color: SRGBColor) { self.init(red: color.red, green: color.green, blue: color.blue) }
}

/// Every colour comes from `RacingPalette`, whose contrast is covered by unit tests.
enum RacingStyle {
    /// Blocks, rules and white-on-red labels only; it is too dark to use as text on the background.
    static let red = Color(RacingPalette.brandRed)
    static let accentText = Color(RacingPalette.accentText)
    static let onRed = Color(RacingPalette.onBrandRed)
    static let background = Color(RacingPalette.background)
    static let surface = Color(RacingPalette.surface)
    static let raised = Color(RacingPalette.raised)
    static let textPrimary = Color(RacingPalette.textPrimary)
    static let textSecondary = Color(RacingPalette.textSecondary)
    static let textTertiary = Color(RacingPalette.textTertiary)
    static let trackEdge = Color(RacingPalette.trackEdge)
    static let trackSurface = Color(RacingPalette.trackSurface)

    /// Spacing scale. Every gap and padding in the app is one of these.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    /// Corner radii. Chips and badges are `Capsule()`.
    enum Radius {
        static let card: CGFloat = 12
        static let row: CGFloat = 8
        /// The thin team-colour tag beside a driver.
        static let tag: CGFloat = 2
    }

    /// The type scale, defined once. System default design (never rounded); heavy and black
    /// for display and headlines; every size is a text style so Dynamic Type still applies.
    enum Typography {
        /// Circuit and race names: the one big line on a screen.
        static let display = Font.system(.largeTitle, weight: .black)
        /// Section and card titles.
        static let title = Font.system(.title2, weight: .heavy)
        static let headline = Font.system(.headline, weight: .heavy)
        static let body = Font.system(.body)
        static let bodyStrong = Font.system(.body, weight: .semibold)
        static let caption = Font.system(.caption)
        /// Short column and chip labels. Pair with `.racingLabel()` for case and tracking.
        static let label = Font.system(.caption2, weight: .bold)
        /// Timing data: gaps, lap times, clock times.
        static let data = Font.system(.callout, weight: .medium).monospacedDigit()
        /// The large figure in a row: position and countdown.
        static let figure = Font.system(.title2, weight: .black).monospacedDigit()
        /// Titles and numbers of rows that are over (past races): same size, lighter weight.
        static let headlineQuiet = Font.system(.headline, weight: .medium)
        static let figureQuiet = Font.system(.title2, weight: .semibold).monospacedDigit()
        /// Three-letter driver codes.
        static let code = Font.system(.headline, weight: .black)
    }
}

extension FeedStatus {
    var fill: Color {
        if isDemo { return Color(RacingPalette.statusDemo) }
        switch kind {
        case .live: return Color(RacingPalette.statusLive)
        case .stale: return Color(RacingPalette.statusStale)
        case .offline, .connecting: return Color(RacingPalette.statusOffline)
        }
    }

    /// A different shape per state so colour is never the only cue.
    var symbol: String {
        if isDemo { return "play.circle.fill" }
        switch kind {
        case .live: return "dot.radiowaves.left.and.right"
        case .stale: return "clock.badge.exclamationmark"
        case .offline: return "wifi.slash"
        case .connecting: return "arrow.triangle.2.circlepath"
        }
    }
}

/// Resolves the feed status once a second for whichever small view asks. Keeping the clock here, and not
/// above the tab bar, means a tick redraws only the pill and the hero line, never the scrolling content.
/// Every instance ticks on the same whole-second boundaries, so the pill and the hero cannot disagree.
struct FeedClock<Content: View>: View {
    let store: TimingStore
    @ViewBuilder let content: (FeedStatus) -> Content

    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 1)) { context in
            content(FeedStatus.resolve(snapshot: store.snapshot, connected: store.connected,
                                       hasError: store.error != nil, now: context.date))
        }
    }
}

struct FeedStatusPill: View {
    let status: FeedStatus

    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(RacingStyle.Typography.label)
            .foregroundStyle(Color(RacingPalette.onStatus))
            .padding(.horizontal, RacingStyle.Space.m).padding(.vertical, RacingStyle.Space.xs)
            .background(status.fill, in: Capsule())
            .lineLimit(1).fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Feed status")
            .accessibilityValue(status.spokenDescription)
    }
}

extension RaceControlKind {
    var color: Color {
        switch self {
        case .green, .clear: Color(RacingPalette.flagGreen)
        case .yellow, .doubleYellow: Color(RacingPalette.flagYellow)
        case .red, .black: Color(RacingPalette.flagRed)
        case .blue: Color(RacingPalette.flagBlue)
        case .safetyCar, .virtualSafetyCar: Color(RacingPalette.flagSafetyCar)
        case .blackAndWhite, .chequered, .info: Color(RacingPalette.flagNeutral)
        }
    }

    var symbol: String {
        switch self {
        case .chequered: "flag.checkered"
        case .safetyCar, .virtualSafetyCar: "car.fill"
        case .red, .black: "exclamationmark.octagon.fill"
        case .yellow, .doubleYellow, .blackAndWhite: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        default: "flag.fill"
        }
    }
}

struct RacingSectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: RacingStyle.Space.xs) {
            Text(title).font(RacingStyle.Typography.title).racingHeading()
            if let subtitle {
                Text(subtitle).font(RacingStyle.Typography.caption).foregroundStyle(RacingStyle.textSecondary)
            }
        }.accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
    }
}

/// Cards pad by `Space.l` on compact width (phones) and `Space.xl` otherwise; `.compact` is for list rows.
struct RacingCard: ViewModifier {
    enum Density { case regular, compact }
    var density: Density = .regular
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content
            .padding(density == .compact ? RacingStyle.Space.m : sizeClass == .compact ? RacingStyle.Space.l : RacingStyle.Space.xl)
            .background(RacingStyle.surface, in: RoundedRectangle(cornerRadius: RacingStyle.Radius.card))
    }
}

/// Page margin: `Space.l` on compact width, `Space.xl` otherwise.
struct RacingPagePadding: ViewModifier {
    var edges: Edge.Set = .all
    @Environment(\.horizontalSizeClass) private var sizeClass
    func body(content: Content) -> some View {
        content.padding(edges, sizeClass == .compact ? RacingStyle.Space.l : RacingStyle.Space.xl)
    }
}

extension View {
    func racingCard(_ density: RacingCard.Density = .regular) -> some View { modifier(RacingCard(density: density)) }
    func racingPagePadding(_ edges: Edge.Set = .all) -> some View { modifier(RacingPagePadding(edges: edges)) }
    /// Short uppercase labels only: column headers, chips, eyebrows.
    /// Headings stop growing at accessibility2 so a title can never push the data off the screen.
    func racingHeading() -> some View { dynamicTypeSize(...DynamicTypeSize.accessibility2) }
    func racingLabel() -> some View { font(RacingStyle.Typography.label).textCase(.uppercase).tracking(1) }
}

struct TyreBadge: View {
    let compound: TyreCompound
    @ScaledMetric(relativeTo: .caption) private var diameter = 26

    private var color: Color {
        switch compound {
        case .soft: Color(RacingPalette.tyreSoft)
        case .medium: Color(RacingPalette.tyreMedium)
        case .hard: Color(RacingPalette.tyreHard)
        case .intermediate: Color(RacingPalette.tyreIntermediate)
        case .wet: Color(RacingPalette.tyreWet)
        case .unknown: Color(RacingPalette.tyreUnknown)
        }
    }

    var body: some View {
        Text(compound.symbol)
            .font(RacingStyle.Typography.label)
            .foregroundStyle(color)
            .frame(width: diameter, height: diameter)
            .background(color.opacity(0.08), in: Circle())
            .overlay(Circle().strokeBorder(color, lineWidth: 2))
            .accessibilityLabel(compound.label)
    }
}
