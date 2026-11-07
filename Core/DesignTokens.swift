import Foundation

/// An sRGB colour with WCAG 2.x contrast maths. Kept in Core so the palette the
/// app draws with can be checked by tests instead of by eye.
public struct SRGBColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(hex: UInt32) {
        red = Double((hex >> 16) & 255) / 255
        green = Double((hex >> 8) & 255) / 255
        blue = Double(hex & 255) / 255
    }

    /// WCAG relative luminance.
    public var relativeLuminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio, from 1 (identical) to 21 (black on white).
    public func contrastRatio(with other: SRGBColor) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// Every colour the app paints with. Dark-only by design (the official F1 app is
/// dark-first); text colours are explicit rather than `.secondary` so contrast is known.
public enum RacingPalette {
    // Surfaces
    public static let background = SRGBColor(hex: 0x0E0E13)
    public static let surface = SRGBColor(hex: 0x181820)
    public static let raised = SRGBColor(hex: 0x22222C)
    public static let selected = SRGBColor(hex: 0x2C2C38)
    // Text
    public static let textPrimary = SRGBColor(hex: 0xF5F5F7)
    public static let textSecondary = SRGBColor(hex: 0xB8B8C6)
    public static let textTertiary = SRGBColor(hex: 0x9494A6)
    // Borders of interactive controls (WCAG 1.4.11 needs 3:1). Cards have no border.
    public static let controlBorder = SRGBColor(hex: 0x7A7A8C)
    // Brand accent: blocks, rules and white-on-red labels only. Never text on dark (4.1:1).
    public static let brandRed = SRGBColor(hex: 0xE80805)
    public static let onBrandRed = SRGBColor(hex: 0xFFFFFF)
    // Lighter red for the tab-bar tint and other accent text; passes AA on every surface.
    public static let accentText = SRGBColor(hex: 0xFF6259)
    // Feed status fills; label text on them is `onStatus`.
    public static let statusLive = SRGBColor(hex: 0x35D07F)
    public static let statusDemo = SRGBColor(hex: 0xFFC53D)
    public static let statusStale = SRGBColor(hex: 0xFF8A3D)
    public static let statusOffline = SRGBColor(hex: 0x8E8EA0)
    public static let onStatus = SRGBColor(hex: 0x0E0E13)
    // Track map: a dark kerb outline around a lighter racing surface.
    public static let trackEdge = SRGBColor(hex: 0x08080B)
    public static let trackSurface = SRGBColor(hex: 0x74748A)
    // Tyre rings. Soft is a lighter coral than the brand red so the two never read as one.
    public static let tyreSoft = SRGBColor(hex: 0xFF6B6B)
    public static let tyreMedium = SRGBColor(hex: 0xFFD60A)
    public static let tyreHard = SRGBColor(hex: 0xFFFFFF)
    public static let tyreIntermediate = SRGBColor(hex: 0x39D353)
    public static let tyreWet = SRGBColor(hex: 0x3DA9FF)
    public static let tyreUnknown = SRGBColor(hex: 0x9494A6)
    // Race-control flags
    public static let flagGreen = SRGBColor(hex: 0x35D07F)
    public static let flagYellow = SRGBColor(hex: 0xFFD60A)
    public static let flagRed = SRGBColor(hex: 0xFF453A)
    public static let flagBlue = SRGBColor(hex: 0x3DA9FF)
    public static let flagSafetyCar = SRGBColor(hex: 0xFF9F0A)
    public static let flagNeutral = SRGBColor(hex: 0xF5F5F7)
}
