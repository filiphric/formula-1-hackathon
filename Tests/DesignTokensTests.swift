import Foundation
import Testing
@testable import FormulaCore

private let surfaces = [RacingPalette.background, RacingPalette.surface, RacingPalette.raised, RacingPalette.selected]

@Test func contrastMathMatchesWCAGReferenceValues() {
    let black = SRGBColor(hex: 0x000000), white = SRGBColor(hex: 0xFFFFFF)
    #expect(abs(black.contrastRatio(with: white) - 21) < 0.001)
    #expect(abs(white.contrastRatio(with: white) - 1) < 0.001)
    // #767676 on white is the well-known smallest grey that passes AA (4.54:1).
    #expect(abs(SRGBColor(hex: 0x767676).contrastRatio(with: white) - 4.54) < 0.01)
}

@Test func textColoursMeetAAOnEverySurface() {
    for surface in surfaces {
        #expect(RacingPalette.textPrimary.contrastRatio(with: surface) >= 4.5)
        #expect(RacingPalette.textSecondary.contrastRatio(with: surface) >= 4.5)
        #expect(RacingPalette.textTertiary.contrastRatio(with: surface) >= 4.5)
    }
}

@Test func controlBordersMeetNonTextContrastOnEverySurface() {
    for surface in surfaces { #expect(RacingPalette.controlBorder.contrastRatio(with: surface) >= 3) }
}

@Test func brandRedFailsAsTextOnDarkSoItIsOnlyUsedForBlocksWithWhiteLabels() {
    #expect(RacingPalette.brandRed.contrastRatio(with: RacingPalette.background) < 4.5)
    #expect(RacingPalette.onBrandRed.contrastRatio(with: RacingPalette.brandRed) >= 4.5)
}

@Test func accentTextRedMeetsAAOnEverySurface() {
    for surface in surfaces { #expect(RacingPalette.accentText.contrastRatio(with: surface) >= 4.5) }
}

@Test func statusLabelsAreReadableOnTheirFills() {
    for fill in [RacingPalette.statusLive, RacingPalette.statusDemo, RacingPalette.statusStale, RacingPalette.statusOffline] {
        #expect(RacingPalette.onStatus.contrastRatio(with: fill) >= 4.5)
    }
}

@Test func tyreRingsAreVisibleAndSoftIsNotBrandRed() {
    let rings = [RacingPalette.tyreSoft, RacingPalette.tyreMedium, RacingPalette.tyreHard,
                 RacingPalette.tyreIntermediate, RacingPalette.tyreWet, RacingPalette.tyreUnknown]
    for ring in rings {
        for surface in surfaces { #expect(ring.contrastRatio(with: surface) >= 4.5) }
    }
    #expect(RacingPalette.tyreSoft.contrastRatio(with: RacingPalette.brandRed) >= 1.4)
}

@Test func flagColoursAreVisibleOnRaisedSurface() {
    let flags = [RacingPalette.flagGreen, RacingPalette.flagYellow, RacingPalette.flagRed,
                 RacingPalette.flagBlue, RacingPalette.flagSafetyCar, RacingPalette.flagNeutral]
    for flag in flags { #expect(flag.contrastRatio(with: RacingPalette.raised) >= 3) }
}
