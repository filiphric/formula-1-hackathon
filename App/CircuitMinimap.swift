import SwiftUI

/// The lap as one smooth closed line, fitted inside whatever rectangle it is given and centred in it.
private struct CircuitOutline: Shape {
    let shape: CircuitShape

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / shape.width, rect.height / shape.height)
        let originX = rect.minX + (rect.width - shape.width * scale) / 2
        let originY = rect.minY + (rect.height - shape.height * scale) / 2
        let points = shape.points.map { CGPoint(x: originX + $0.x * scale, y: originY + $0.y * scale) }
        func middle(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        var path = Path()
        guard let last = points.last else { return path }
        // Each outline point becomes the control point of a curve between the midpoints beside it,
        // which rounds the corners the simplified outline would otherwise have.
        path.move(to: middle(last, points[0]))
        for index in points.indices {
            path.addQuadCurve(to: middle(points[index], points[(index + 1) % points.count]), control: points[index])
        }
        path.closeSubpath()
        return path
    }
}

/// A small illustration of a circuit for the calendar. Decorative: the circuit's name is already spoken
/// beside it, so it is hidden from VoiceOver. A circuit without a published outline shows a quiet map symbol
/// in the same box, so rows keep their alignment.
struct CircuitMinimap: View {
    let circuit: String
    let color: Color
    var size = CGSize(width: 56, height: 40)
    var lineWidth: CGFloat = 2.5

    var body: some View {
        Group {
            if let shape = CircuitShape.forCircuit(circuit) {
                CircuitOutline(shape: shape)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    .padding(lineWidth)
            } else {
                Image(systemName: "map").font(RacingStyle.Typography.bodyStrong).foregroundStyle(RacingStyle.textTertiary)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}
