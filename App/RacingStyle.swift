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
    static let headerRed = Color(red: 0.55, green: 0.02, blue: 0.02)
    static let background = Color(RacingPalette.background)
    static let surface = Color(RacingPalette.surface)
    static let raised = Color(RacingPalette.raised)
    static let textPrimary = Color(RacingPalette.textPrimary)
    static let textSecondary = Color(RacingPalette.textSecondary)
    static let textTertiary = Color(RacingPalette.textTertiary)
    static let heading = Font.system(.title2, design: .rounded, weight: .black)
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

struct FeedStatusPill: View {
    let status: FeedStatus

    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(.caption.bold())
            .foregroundStyle(Color(RacingPalette.onStatus))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(status.fill, in: Capsule())
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
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            UnevenRoundedRectangle(topLeadingRadius: 2, bottomTrailingRadius: 5)
                .fill(RacingStyle.red).frame(width: 5, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased()).font(.system(.headline, design: .rounded, weight: .heavy))
                Text(subtitle).font(.caption).foregroundStyle(RacingStyle.textSecondary)
            }
        }.accessibilityElement(children: .combine)
    }
}

struct RacingCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(RacingStyle.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct RacingStripes: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<12 {
                let x = size.width - CGFloat(index) * 24
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: 0))
                stripe.addLine(to: CGPoint(x: x - size.height, y: size.height))
                context.stroke(stripe, with: .color(.white.opacity(0.045)), lineWidth: 10)
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

extension View {
    func racingCard() -> some View { modifier(RacingCard()) }
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
            .font(.system(.caption, design: .rounded, weight: .heavy))
            .foregroundStyle(color)
            .frame(width: diameter, height: diameter)
            .background(color.opacity(0.08), in: Circle())
            .overlay(Circle().strokeBorder(color, lineWidth: 2))
            .accessibilityLabel(compound.label)
    }
}
