import Foundation

/// Physical positions use the GameController extended-gamepad naming convention.
public enum ControllerControl: String, CaseIterable, Codable, Identifiable {
    case south, east, west, north, up, down, left, right
    case leftShoulder, rightShoulder, leftTrigger, rightTrigger
    case menu, options, home, leftStick, rightStick
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .south: return "South (A / Cross)"
        case .east: return "East (B / Circle)"
        case .west: return "West (X / Square)"
        case .north: return "North (Y / Triangle)"
        case .up: return "D-pad up"
        case .down: return "D-pad down"
        case .left: return "D-pad left"
        case .right: return "D-pad right"
        case .leftShoulder: return "Left shoulder"
        case .rightShoulder: return "Right shoulder"
        case .leftTrigger: return "Left trigger"
        case .rightTrigger: return "Right trigger"
        case .menu: return "Menu"
        case .options: return "Options"
        case .home: return "Home"
        case .leftStick: return "Left stick press"
        case .rightStick: return "Right stick press"
        }
    }
}

public enum GameButton: String, CaseIterable, Codable, Identifiable {
    case a, b, x, y, up, down, left, right, l, r, zl, zr, plus, minus, home, lStick, rStick
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .up: return "D-pad up"
        case .down: return "D-pad down"
        case .left: return "D-pad left"
        case .right: return "D-pad right"
        case .plus: return "+ / Start"
        case .minus: return "− / Select"
        case .home: return "Home"
        case .lStick: return "Left stick press"
        case .rStick: return "Right stick press"
        default: return rawValue.uppercased()
        }
    }
}

public struct ControllerBindings {
    public static let storageKey = "controllerBindings"
    public static let swapSticksKey = "controllerSwapSticks"
    private static let defaults: [GameButton] = [.b, .a, .y, .x, .up, .down, .left, .right, .l, .r, .zl, .zr, .plus, .minus, .home, .lStick, .rStick]
    private var values: [GameButton]

    public init(serialized: String = "") {
        guard let data = serialized.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([GameButton].self, from: data),
              decoded.count == ControllerControl.allCases.count,
              Set(decoded).count == GameButton.allCases.count else {
            values = Self.defaults
            return
        }
        values = decoded
    }
    public subscript(_ control: ControllerControl) -> GameButton {
        values[ControllerControl.allCases.firstIndex(of: control)!]
    }
    /// Each button is assigned once; changing a binding swaps the former assignment.
    public mutating func assign(_ button: GameButton, to control: ControllerControl) {
        let index = ControllerControl.allCases.firstIndex(of: control)!
        let other = values.firstIndex(of: button)!
        values.swapAt(index, other)
    }
    public var serialized: String {
        String(data: try! JSONEncoder().encode(values), encoding: .utf8)!
    }
}
