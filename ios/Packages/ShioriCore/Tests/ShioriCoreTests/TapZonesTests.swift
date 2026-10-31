import Foundation
import Testing
@testable import ShioriCore

private let width = 440.0
private let height = 956.0

private func action(_ fx: Double, _ fy: Double, _ layout: TapZoneLayout, bothSidesForward: Bool = false) -> TapAction {
    TapZones.action(x: fx * width, y: fy * height, width: width, height: height,
                    layout: layout, bothSidesForward: bothSidesForward)
}

/// Steps of 1/40 never land exactly on a third, where mirroring could round across a border.
private let grid: [(Double, Double)] = (0...40).flatMap { i in (0...40).map { j in (Double(i) / 40, Double(j) / 40) } }

@Test func standardThirds() {
    for fy in [0.1, 0.5, 0.9] {
        #expect(action(0.1, fy, .standard) == .back)
        #expect(action(0.5, fy, .standard) == .menu)
        #expect(action(0.9, fy, .standard) == .forward)
    }
}

@Test func rightHandedBackIsTopLeftOnly() {
    #expect(action(0.1, 0.2, .rightHanded) == .back)
    #expect(action(0.1, 0.8, .rightHanded) == .forward)
    #expect(action(0.5, 0.5, .rightHanded) == .menu)
    #expect(action(0.5, 0.9, .rightHanded) == .forward)
    #expect(action(0.5, 0.1, .rightHanded) == .forward)
    #expect(action(0.9, 0.2, .rightHanded) == .forward)
}

@Test func leftHandedMirrors() {
    for (fx, fy) in grid {
        #expect(action(fx, fy, .rightHanded) == action(1 - fx, fy, .leftHanded), "at (\(fx), \(fy))")
    }
    #expect(action(0.9, 0.2, .leftHanded) == .back)
}

@Test func bothSidesForwardNeverGoesBack() {
    for layout in TapZoneLayout.allCases {
        for (fx, fy) in grid {
            let plain = action(fx, fy, layout)
            let forward = action(fx, fy, layout, bothSidesForward: true)
            #expect(forward != .back, "\(layout) at (\(fx), \(fy))")
            #expect((plain == .menu) == (forward == .menu), "\(layout) at (\(fx), \(fy))")
        }
    }
    #expect(action(0.1, 0.5, .standard, bothSidesForward: true) == .forward)
}

@Test func pointsOffThePageClampToItsEdges() {
    #expect(TapZones.action(x: -5, y: 400, width: width, height: height, layout: .standard,
                            bothSidesForward: false) == .back)
    #expect(TapZones.action(x: width + 5, y: 400, width: width, height: height, layout: .standard,
                            bothSidesForward: false) == .forward)
    #expect(TapZones.action(x: 10, y: 10, width: 0, height: 0, layout: .standard,
                            bothSidesForward: false) == .menu)
}
