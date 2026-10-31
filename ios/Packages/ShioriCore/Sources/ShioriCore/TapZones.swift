import Foundation

public enum TapZoneLayout: String, Codable, CaseIterable, Sendable {
    case standard, rightHanded, leftHanded
}

public enum TapAction: Equatable, Sendable {
    case back, forward, menu
}

/// Where a tap on the reading page goes (spec §7.6).
///
/// - Standard: the left third goes back, the right third forward, the centre third shows the
///   menu, each at full height.
/// - Right-handed: back is only the left third of the top half, out of a right thumb's way; the
///   menu is the centre third between 25% and 75% of the height; everything else goes forward.
/// - Left-handed: right-handed, mirrored.
public enum TapZones {
    public static func action(x: Double, y: Double, width: Double, height: Double,
                              layout: TapZoneLayout, bothSidesForward: Bool) -> TapAction {
        guard width > 0, height > 0 else { return .menu }
        let fx = min(max(x / width, 0), 1)
        let fy = min(max(y / height, 0), 1)
        let zone: TapAction
        switch layout {
        case .standard: zone = standard(fx)
        case .rightHanded: zone = rightHanded(fx, fy)
        case .leftHanded: zone = rightHanded(1 - fx, fy)
        }
        return bothSidesForward && zone == .back ? .forward : zone
    }

    private static func standard(_ fx: Double) -> TapAction {
        if fx < 1.0 / 3 { return .back }
        if fx >= 2.0 / 3 { return .forward }
        return .menu
    }

    private static func rightHanded(_ fx: Double, _ fy: Double) -> TapAction {
        if fx < 1.0 / 3, fy < 0.5 { return .back }
        if fx >= 1.0 / 3, fx < 2.0 / 3, fy >= 0.25, fy < 0.75 { return .menu }
        return .forward
    }
}
