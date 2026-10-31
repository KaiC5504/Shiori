import Foundation
import Testing
@testable import ShioriCore

private let paperLight: UInt32 = 0xF2ECE3
private let paperDark: UInt32 = 0x1F1F1F

@Test func ratioMatchesWCAGReferencePairs() {
    #expect(abs(AccentContrast.ratio(0x000000, 0xFFFFFF) - 21) < 0.001)
    #expect(abs(AccentContrast.ratio(0xFFFFFF, 0x777777) - 4.48) < 0.01)
    #expect(AccentContrast.ratio(0x777777, 0xFFFFFF) == AccentContrast.ratio(0xFFFFFF, 0x777777))
    #expect(AccentContrast.ratio(0x24222A, 0x24222A) == 1)
}

@Test func paleAccentIsDarkenedForLightPaperAndFlagged() {
    let pale: UInt32 = 0xF6E7A1
    let fix = AccentContrast.fixed(accent: pale, paperLight: paperLight, paperDark: paperDark)
    #expect(fix.adjusted)
    #expect(fix.light != pale)
    #expect(AccentContrast.ratio(fix.light, paperLight) >= 4.5)
    #expect(fix.dark == pale)
}

@Test func deepAccentKeepsItsLightValueAndGetsALighterDarkPartner() {
    let deep: UInt32 = 0x2E4A78
    let fix = AccentContrast.fixed(accent: deep, paperLight: paperLight, paperDark: paperDark)
    #expect(!fix.adjusted)
    #expect(fix.light == deep)
    #expect(AccentContrast.luminance(fix.dark) > AccentContrast.luminance(deep))
    #expect(AccentContrast.ratio(fix.dark, paperDark) >= 4.5)
}

@Test func midToneChangesOnBothSides() {
    let fix = AccentContrast.fixed(accent: 0xFF0000, paperLight: paperLight, paperDark: paperDark)
    #expect(fix.adjusted)
    #expect(AccentContrast.ratio(fix.light, paperLight) >= 4.5)
    #expect(AccentContrast.ratio(fix.dark, paperDark) >= 4.5)
}

@Test func hexRoundTrips() {
    #expect(HexColour.string(0xA9402B) == "#A9402B")
    #expect(HexColour.string(0x00000F) == "#00000F")
    #expect(HexColour.parse("#a9402b") == 0xA9402B)
    #expect(HexColour.parse("fa0") == 0xFFAA00)
    #expect(HexColour.parse("12345") == nil)
    #expect(HexColour.parse("GG0000") == nil)
}
