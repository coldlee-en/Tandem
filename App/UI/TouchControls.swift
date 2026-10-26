import SwiftUI
import UIKit

/// Each control owns its touch so a held direction and face button work together.
struct HoldButton: UIViewRepresentable {
    let title: String
    let action: (Bool) -> Void
    var prominent = false

    func makeUIView(context: Context) -> PressControl {
        let view = PressControl()
        view.accessibilityLabel = title
        view.label.text = title
        view.onChange = action
        view.prominent = prominent
        return view
    }
    func updateUIView(_ view: PressControl, context: Context) {
        view.onChange = action
        view.prominent = prominent
    }
}

final class PressControl: UIControl {
    let label = UILabel()
    var onChange: ((Bool) -> Void)?
    var prominent = false { didSet { updateAppearance() } }
    private var pressed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isExclusiveTouch = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        addSubview(label)
        layer.borderWidth = 1
        updateAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        setPressed(true)
        return true
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        setPressed(bounds.insetBy(dx: -18, dy: -18).contains(touch.location(in: self)))
        return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) { setPressed(false) }
    override func cancelTracking(with event: UIEvent?) { setPressed(false) }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { setPressed(false) }
    }
    override func accessibilityActivate() -> Bool {
        setPressed(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.setPressed(false) }
        return true
    }
    private func setPressed(_ value: Bool) {
        guard value != pressed else { return }
        pressed = value
        onChange?(value)
        updateAppearance()
    }
    private func updateAppearance() {
        backgroundColor = pressed ? UIColor(red: 0.50, green: 0.93, blue: 0.77, alpha: 0.8) : UIColor(white: 1, alpha: prominent ? 0.12 : 0.055)
        layer.borderColor = UIColor(white: 1, alpha: pressed ? 0.3 : 0.09).cgColor
        label.textColor = pressed ? .black : UIColor(white: 0.9, alpha: 1)
    }
}

struct AnalogStick: UIViewRepresentable {
    let label: String
    let action: (Float, Float) -> Void
    func makeUIView(context: Context) -> AnalogControl {
        let view = AnalogControl()
        view.onChange = action
        view.accessibilityLabel = label
        return view
    }
    func updateUIView(_ view: AnalogControl, context: Context) { view.onChange = action }
}

final class AnalogControl: UIControl {
    var onChange: ((Float, Float) -> Void)?
    private let thumb = UIView()
    private var value = CGPoint.zero
    override init(frame: CGRect) {
        super.init(frame: frame)
        isExclusiveTouch = false
        backgroundColor = UIColor(white: 1, alpha: 0.035)
        layer.borderColor = UIColor(white: 1, alpha: 0.1).cgColor
        layer.borderWidth = 1
        thumb.backgroundColor = UIColor(white: 1, alpha: 0.15)
        thumb.isUserInteractionEnabled = false
        addSubview(thumb)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
        let diameter = min(bounds.width, bounds.height) * 0.5
        thumb.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        thumb.layer.cornerRadius = diameter / 2
        positionThumb()
    }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool { move(touch); return true }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool { move(touch); return true }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) { reset() }
    override func cancelTracking(with event: UIEvent?) { reset() }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { reset() } }
    private func move(_ touch: UITouch) {
        let point = touch.location(in: self)
        let radius = max(1, min(bounds.width, bounds.height) * 0.35)
        var x = (point.x - bounds.midX) / radius
        var y = (point.y - bounds.midY) / radius
        let length = hypot(x, y)
        if length > 1 { x /= length; y /= length }
        value = CGPoint(x: x, y: y)
        positionThumb()
        // Emulator convention is positive Y up.
        onChange?(Float(x), Float(-y))
    }
    private func reset() { value = .zero; positionThumb(); onChange?(0, 0) }
    private func positionThumb() {
        let radius = min(bounds.width, bounds.height) * 0.25
        thumb.center = CGPoint(x: bounds.midX + value.x * radius, y: bounds.midY + value.y * radius)
    }
}

@MainActor
struct ControllerSide: View {
    let session: EmulationSession
    let left: Bool
    var compact = false
    var body: some View {
        VStack(spacing: compact ? 8 : 14) {
            HStack(spacing: 8) {
                control(left ? "ZL" : "ZR", left ? .zl : .zr).frame(width: 48, height: 30)
                control(left ? "L" : "R", left ? .l : .r).frame(width: 48, height: 30)
            }
            if left {
                AnalogStick(label: "Left stick") { session.setStick(.left, x: $0, y: $1) }.frame(width: compact ? 65 : 76, height: compact ? 65 : 76)
                diamond(up: ("↑", .up), down: ("↓", .down), left: ("←", .left), right: ("→", .right))
            } else {
                diamond(up: ("X", .x), down: ("B", .b), left: ("Y", .y), right: ("A", .a))
                AnalogStick(label: "Right stick") { session.setStick(.right, x: $0, y: $1) }.frame(width: compact ? 65 : 76, height: compact ? 65 : 76)
            }
        }
    }
    private func control(_ label: String, _ button: EmulatorButton) -> some View {
        HoldButton(title: label, action: { session.setButton(button, pressed: $0) }, prominent: button == .a)
    }
    private func diamond(up: (String, EmulatorButton), down: (String, EmulatorButton), left: (String, EmulatorButton), right: (String, EmulatorButton)) -> some View {
        let side: CGFloat = compact ? 31 : 36
        return VStack(spacing: -8) {
            control(up.0, up.1).frame(width: side, height: side)
            HStack(spacing: side - 14) {
                control(left.0, left.1).frame(width: side, height: side)
                control(right.0, right.1).frame(width: side, height: side)
            }
            control(down.0, down.1).frame(width: side, height: side)
        }
    }
}
