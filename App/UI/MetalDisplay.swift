import SwiftUI
import Metal
import QuartzCore
import UIKit
import EmulationKit

@MainActor
struct MetalDisplay: UIViewRepresentable {
    let session: EmulationSession
    let system: GameSystem
    func makeUIView(context: Context) -> ScreenPairView {
        let view = ScreenPairView(dualScreen: system == .nintendo3DS)
        view.onAttach = { primary, secondary in
            Task { await session.attach(primary: primary, secondary: secondary) }
        }
        view.secondary.onTouch = { phase, x, y in session.touch(phase, x: x, y: y) }
        view.primary.onTouch = { phase, x, y in session.touch(phase, x: x, y: y) }
        return view
    }
    func updateUIView(_ uiView: ScreenPairView, context: Context) {}
}

final class ScreenPairView: UIView {
    let primary = MetalScreenView()
    let secondary = MetalScreenView()
    var onAttach: ((CAMetalLayer, CAMetalLayer?) -> Void)?
    private let dualScreen: Bool
    private var previousSize = CGSize.zero
    init(dualScreen: Bool) {
        self.dualScreen = dualScreen
        super.init(frame: .zero)
        backgroundColor = .clear
        primary.isUserInteractionEnabled = !dualScreen
        addSubview(primary)
        if dualScreen { addSubview(secondary) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() { super.didMoveToWindow(); setNeedsLayout() }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if dualScreen {
            let scale = min(bounds.width / 400, bounds.height / 488)
            let totalHeight = 488 * scale
            primary.frame = CGRect(x: (bounds.width - 400 * scale) / 2, y: (bounds.height - totalHeight) / 2, width: 400 * scale, height: 240 * scale)
            secondary.frame = CGRect(x: (bounds.width - 320 * scale) / 2, y: primary.frame.maxY + 8 * scale, width: 320 * scale, height: 240 * scale)
        } else {
            let scale = min(bounds.width / 1280, bounds.height / 720)
            primary.frame = CGRect(x: (bounds.width - 1280 * scale) / 2, y: (bounds.height - 720 * scale) / 2, width: 1280 * scale, height: 720 * scale)
        }
        primary.layoutIfNeeded()
        secondary.layoutIfNeeded()
        guard window != nil, previousSize != primary.bounds.size else { return }
        previousSize = primary.bounds.size
        onAttach?(primary.metalLayer, dualScreen ? secondary.metalLayer : nil)
    }
}

final class MetalScreenView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    var onTouch: ((TouchPhase, Float, Float) -> Void)?
    private var activeTouch: UITouch?
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque = true
        isMultipleTouchEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.nativeScale ?? UIScreen.main.nativeScale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        send(.began, touch: touch)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        send(.moved, touch: touch)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }
    private func finish(_ touches: Set<UITouch>) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        send(.ended, touch: touch)
        activeTouch = nil
    }
    private func send(_ phase: TouchPhase, touch: UITouch) {
        let point = touch.location(in: self)
        onTouch?(phase, Float(min(1, max(0, point.x / max(1, bounds.width)))), Float(min(1, max(0, point.y / max(1, bounds.height)))))
    }
}
