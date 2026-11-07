import SwiftUI

/// Shared visual language for the race centre and calendar.
enum RacingStyle {
    static let red = Color(red: 0.91, green: 0.035, blue: 0.02)
    static let headerRed = Color(red: 0.55, green: 0.02, blue: 0.02)
    static let background = Color(red: 0.065, green: 0.065, blue: 0.09)
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.135)
    static let border = Color.white.opacity(0.14)
    static let heading = Font.system(.title2, design: .rounded, weight: .black)
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
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}

struct RacingCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(RacingStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(RacingStyle.border))
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
        case .soft: .red
        case .medium: .yellow
        case .hard: .white
        case .intermediate: .green
        case .wet: .cyan
        case .unknown: .gray
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
