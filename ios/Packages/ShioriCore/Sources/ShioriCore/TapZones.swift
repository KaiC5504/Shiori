import Foundation

public enum TapZoneLayout: String, Codable, CaseIterable, Sendable {
    case standard, rightHanded, leftHanded
}

public enum TapAction: Equatable, Sendable {
    case back, forward, menu
}

/// Where a tap on the reading page goes (spec §7.6).
public enum TapZones {
    // Stub from the wave 3 contracts commit; R1 implements it.
    public static func action(x: Double, y: Double, width: Double, height: Double,
                              layout: TapZoneLayout, bothSidesForward: Bool) -> TapAction {
        .menu
    }
}
