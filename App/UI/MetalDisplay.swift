import SwiftUI
import Metal
import QuartzCore
import UIKit
import EmulationKit

@MainActor
struct MetalDisplay: UIViewRepresentable {
    let session: EmulationSession
    let system: GameSystem
    var configuration = PlayerConfiguration()
    func makeUIView(context: Context) -> ScreenPairView {
        let view = ScreenPairView(dualScreen: system == .nintendo3DS, configuration: configuration)
        view.onAttach = { primary, secondary in
            Task { await session.attach(primary: primary, secondary: secondary) }
        }
        view.secondary.onTouch = { phase, x, y in session.touch(phase, x: x, y: y) }
        view.primary.onTouch = { phase, x, y in session.touch(phase, x: x, y: y) }
        return view
    }
    func updateUIView(_ uiView: ScreenPairView, context: Context) {
        if uiView.configuration != configuration {
            uiView.configuration = configuration
            uiView.setNeedsLayout()
        }
    }
}

final class ScreenPairView: UIView {
    let primary = MetalScreenView()
    let secondary = MetalScreenView()
    var onAttach: ((CAMetalLayer, CAMetalLayer?) -> Void)?
    private let dualScreen: Bool
    var configuration: PlayerConfiguration
    private var previousDrawables: [CGSize] = []
    init(dualScreen: Bool, configuration: PlayerConfiguration = PlayerConfiguration()) {
        self.configuration = configuration
        self.dualScreen = dualScreen
        super.init(frame: .zero)
        backgroundColor = .clear
        primary.isUserInteractionEnabled = !dualScreen
        addSubview(primary)
        if dualScreen { addSubview(secondary) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        previousDrawables = []
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if dualScreen {
            let frames = PlayerScreenFrames.calculate(in: bounds, configuration: configuration)
            primary.frame = frames.primary
            secondary.frame = frames.secondary
        } else {
            let scale = min(bounds.width / 1280, bounds.height / 720)
            primary.frame = CGRect(x: (bounds.width - 1280 * scale) / 2, y: (bounds.height - 720 * scale) / 2, width: 1280 * scale, height: 720 * scale)
        }
        primary.layoutIfNeeded()
        secondary.layoutIfNeeded()
        let drawables = [primary.metalLayer.drawableSize, secondary.metalLayer.drawableSize]
        guard window != nil, previousDrawables != drawables else { return }
        previousDrawables = drawables
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
