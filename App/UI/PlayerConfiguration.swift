import Foundation

enum PlayerScreenLayout: String, Codable, CaseIterable, Identifiable {
    case stacked, sideBySide, topFocus
    var id: String { rawValue }
    var label: String {
        switch self {
        case .stacked: return "Stacked"
        case .sideBySide: return "Side by side"
        case .topFocus: return "Top screen focus"
        }
    }
}

struct ControlAnchor: Codable, Equatable {
    var x: Double
    var y: Double
}

struct PlayerConfiguration: Codable, Equatable {
    static let portraitKey = "playerLayout.portrait.v1"
    static let landscapeKey = "playerLayout.landscape.v1"
    var layout: PlayerScreenLayout = .stacked
    var screenScale: Double = 1
    var screenGap: Double = 8
    var controlScale: Double = 1
    var controlOpacity: Double = 1
    var showControls = true
    var left = ControlAnchor(x: 0.2, y: 0.80)
    var right = ControlAnchor(x: 0.8, y: 0.80)
    var menu = ControlAnchor(x: 0.5, y: 0.95)

    static func defaults(landscape: Bool) -> Self {
        var value = Self()
        if landscape {
            value.layout = .sideBySide
            value.left = ControlAnchor(x: 0.09, y: 0.5)
            value.right = ControlAnchor(x: 0.91, y: 0.5)
            value.menu = ControlAnchor(x: 0.5, y: 0.94)
        }
        return value
    }

    static func decode(_ text: String, landscape: Bool) -> Self {
        guard let data = text.data(using: .utf8),
              let value = try? JSONDecoder().decode(Self.self, from: data) else {
            return defaults(landscape: landscape)
        }
        return value.sanitized
    }

    var serialized: String {
        guard let data = try? JSONEncoder().encode(sanitized) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    var sanitized: Self {
        var value = self
        func bound(_ x: Double, _ lower: Double, _ upper: Double, fallback: Double) -> Double {
            x.isFinite ? min(upper, max(lower, x)) : fallback
        }
        value.screenScale = bound(screenScale, 0.65, 1, fallback: 1)
        value.screenGap = bound(screenGap, 0, 32, fallback: 8)
        value.controlScale = bound(controlScale, 0.75, 1.15, fallback: 1)
        value.controlOpacity = bound(controlOpacity, 0.25, 1, fallback: 1)
        for path in [\Self.left, \Self.right, \Self.menu] {
            value[keyPath: path].x = bound(value[keyPath: path].x, 0, 1, fallback: 0.5)
            value[keyPath: path].y = bound(value[keyPath: path].y, 0, 1, fallback: 0.5)
        }
        return value
    }
}

struct PlayerScreenFrames {
    let primary: CGRect
    let secondary: CGRect

    static func calculate(in bounds: CGRect, configuration: PlayerConfiguration) -> Self {
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else {
            return Self(primary: .zero, secondary: .zero)
        }
        let config = configuration.sanitized
        let width = bounds.width * CGFloat(config.screenScale)
        let height = bounds.height * CGFloat(config.screenScale)
        let gap = min(CGFloat(config.screenGap), min(width, height) * 0.1)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        switch config.layout {
        case .stacked:
            let scale = max(0, min(width / 400, (height - gap) / 480))
            let y = center.y - (480 * scale + gap) / 2
            return Self(
                primary: CGRect(x: center.x - 200 * scale, y: y, width: 400 * scale, height: 240 * scale),
                secondary: CGRect(x: center.x - 160 * scale, y: y + 240 * scale + gap, width: 320 * scale, height: 240 * scale))
        case .sideBySide:
            let scale = max(0, min((width - gap) / 720, height / 240))
            let x = center.x - (720 * scale + gap) / 2
            return Self(
                primary: CGRect(x: x, y: center.y - 120 * scale, width: 400 * scale, height: 240 * scale),
                secondary: CGRect(x: x + 400 * scale + gap, y: center.y - 120 * scale, width: 320 * scale, height: 240 * scale))
        case .topFocus:
            let scale = max(0, min((width - gap) / 560, height / 240))
            let x = center.x - (560 * scale + gap) / 2
            return Self(
                primary: CGRect(x: x, y: center.y - 120 * scale, width: 400 * scale, height: 240 * scale),
                secondary: CGRect(x: x + 400 * scale + gap, y: center.y, width: 160 * scale, height: 120 * scale))
        }
    }

    static func controlCenter(_ anchor: ControlAnchor, size: CGSize, in bounds: CGRect) -> CGPoint {
        let halfWidth = min(size.width, bounds.width) / 2
        let halfHeight = min(size.height, bounds.height) / 2
        return CGPoint(
            x: min(bounds.maxX - halfWidth, max(bounds.minX + halfWidth, bounds.minX + CGFloat(anchor.x) * bounds.width)),
            y: min(bounds.maxY - halfHeight, max(bounds.minY + halfHeight, bounds.minY + CGFloat(anchor.y) * bounds.height)))
    }
}
