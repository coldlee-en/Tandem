import Foundation
import QuartzCore
import EmulationKit

enum EmulatorButton: CaseIterable, Hashable {
    case a, b, x, y, up, down, left, right, l, r, zl, zr
    case plus, minus, home, lStick, rStick
}

enum EmulatorStick: Hashable { case left, right }
enum TouchPhase { case began, moved, ended }

struct CoreAvailability {
    let isAvailable: Bool
    let summary: String
    let detail: String
}

struct RenderSurfaces {
    let primary: CAMetalLayer
    let secondary: CAMetalLayer?
}

enum EmulationError: LocalizedError {
    case unavailable(String), invalidSurface, startFailed(String), jitRequired

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .startFailed(let message): return message
        case .invalidSurface: return "The display is not ready. Close the player and try again."
        case .jitRequired:
            return "This Switch core requires JIT. Attach Xcode's debugger to the development build before launching a game."
        }
    }
}

/// Core calls are serialized by the main actor; heavy native work belongs on
/// the core's worker thread. The surfaces must outlive stop().
@MainActor
protocol EmulatorCore: AnyObject {
    var system: GameSystem { get }
    var name: String { get }
    func start(gameURL: URL, surfaces: RenderSurfaces, systemDirectory: URL) async throws
    func resize(surfaces: RenderSurfaces) async
    func setPaused(_ paused: Bool) async
    func stop() async
    func setButton(_ button: EmulatorButton, pressed: Bool)
    func setStick(_ stick: EmulatorStick, x: Float, y: Float)
    func touch(_ phase: TouchPhase, x: Float, y: Float)
}

extension EmulatorCore {
    func resize(surfaces: RenderSurfaces) async {}
}

@MainActor
protocol CoreExitReporting: AnyObject {
    var onUnexpectedExit: ((String) -> Void)? { get set }
}
