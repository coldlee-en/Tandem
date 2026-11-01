import Foundation
import QuartzCore
import EmulationKit

#if canImport(Cytrus)
import Cytrus

/// Targets the pinned Cytrus API after scripts/patch_cytrus.py is applied.
@MainActor
final class CytrusCore: EmulatorCore, CoreExitReporting, SaveStateCore {
    let system = GameSystem.nintendo3DS
    let name = "Cytrus · Azahar"
    private static let engine = CytrusSystem()
    private static var initialized = false
    private var loaded = false
    private var surfaces: RenderSurfaces?
    private var monitor: Task<Void, Never>?
    var onUnexpectedExit: ((String) -> Void)?

    func start(gameURL: URL, surfaces: RenderSurfaces, systemDirectory: URL) async throws {
        guard let secondary = surfaces.secondary else { throw EmulationError.invalidSurface }
        let directory = systemDirectory.appendingPathComponent("3DS", isDirectory: true)
        if !Self.initialized {
            await Self.engine.initializeLogging(userDirectory: directory)
            Self.initialized = true
        }
        // An ordinary signed build uses the interpreter. JIT is only selected
        // after the OS reports this development process as debugged.
        await Self.engine.setSetting(setting: .CPU_JIT, value: TandemIsJITEnabled())
        await Self.engine.setSetting(setting: .SHADER_JIT, value: false)
        await Self.engine.setSetting(setting: .RESOLUTION_SCALE_FACTOR, value: 1)
        await Self.engine.setSetting(setting: .NEW_3DS_MODE, value: true)
        self.surfaces = surfaces
        await configure(surfaces.primary, secondary: false)
        await configure(secondary, secondary: true)
        // The upstream callback is optional in our patch; no UI pointer escapes.
        guard await Self.engine.insertDisc(at: gameURL) else {
            let result = await Self.engine.lastLoadResult()
            let message: String
            switch result {
            case 5:
                message = "The game could not be decrypted or verified. Import your console's 3DS AES keys in Settings. Seed-encrypted games also need your seeddb.bin. Check the log for missing keys, seeds, or a failed verification."
            case 2, 6:
                message = "The game has an unsupported or invalid format. Import a complete .3ds/.cci cartridge dump or a supported .cxi/.3dsx file."
            case 10:
                message = "The game requires 3DS system files that are missing. Check System/3DS/log/cytrus_log.txt for the required file."
            default:
                message = "Cytrus could not initialize this game (load status \(result)). See System/3DS/log/cytrus_log.txt for details."
            }
            self.surfaces = nil
            throw EmulationError.startFailed(message)
        }
        loaded = true
        await Self.engine.set(change: true, isPaused: false)
        await Self.engine.set(change: true, isRunning: true)
        await Self.engine.start()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                guard let self, loaded else { return }
                if !(await Self.engine.running) {
                    await stop()
                    onUnexpectedExit?("The 3DS core ended the session. Check System/3DS/log for details.")
                    return
                }
            }
        }
    }

    private func stateAction(_ action: Int32, slot: Int = 0) async throws -> String {
        guard loaded else { throw EmulationError.startFailed("Start a game before using save states.") }
        let response = await Self.engine.stateAction(action: action, slot: Int32(slot))
        guard response.hasPrefix("OK\n") else {
            throw EmulationError.startFailed(response)
        }
        return String(response.dropFirst(3))
    }

    func saveStateSlots() async throws -> [SaveStateSlot] {
        let response = try await stateAction(0)
        var slots = (1...3).map { SaveStateSlot(id: $0, savedAt: nil, compatible: false) }
        for line in response.split(separator: "\n") {
            let fields = line.split(separator: "|")
            guard fields.count == 3, let slot = Int(fields[0]), (1...3).contains(slot),
                  let seconds = Double(fields[1]) else { continue }
            slots[slot - 1] = SaveStateSlot(id: slot, savedAt: Date(timeIntervalSince1970: seconds), compatible: fields[2] == "1")
        }
        return slots
    }

    func saveState(slot: Int) async throws {
        _ = try await stateAction(1, slot: slot)
    }

    func loadState(slot: Int) async throws {
        _ = try await stateAction(2, slot: slot)
    }

    func resize(surfaces: RenderSurfaces) async {
        guard loaded else { return }
        self.surfaces = surfaces
        await configure(surfaces.primary, secondary: false)
        if let secondary = surfaces.secondary { await configure(secondary, secondary: true) }
    }

    private func configure(_ layer: CAMetalLayer, secondary: Bool) async {
        await Self.engine.set(layer: layer, height: layer.drawableSize.height,
                              width: layer.drawableSize.width, secondary: secondary)
    }

    func setPaused(_ paused: Bool) async {
        guard loaded else { return }
        await Self.engine.set(change: true, isPaused: paused)
    }

    func stop() async {
        guard loaded else { return }
        monitor?.cancel()
        monitor = nil
        loaded = false
        await Self.engine.stop()
        surfaces = nil
    }

    func setButton(_ button: EmulatorButton, pressed: Bool) {
        guard loaded, let mapped = Self.buttons[button] else { return }
        if pressed { Self.engine.press(button: mapped) }
        else { Self.engine.release(button: mapped) }
    }

    func setStick(_ stick: EmulatorStick, x: Float, y: Float) {
        guard loaded else { return }
        Self.engine.moveThumbstick(with: stick == .left ? CytrusButton.circlePad.int32 : CytrusButton.cStick.int32, x: x, y: y)
    }

    func touch(_ phase: TouchPhase, x: Float, y: Float) {
        guard loaded, let layer = surfaces?.secondary else { return }
        let point = CGPoint(x: CGFloat(x) * layer.drawableSize.width, y: CGFloat(y) * layer.drawableSize.height)
        Task {
            guard loaded else { return }
            switch phase {
            case .began: await Self.engine.touchBegan(at: point)
            case .moved: await Self.engine.touchMoved(at: point)
            case .ended: await Self.engine.touchEnded()
            }
        }
    }

    private static let buttons: [EmulatorButton: CytrusButton] = [
        .a: .a, .b: .b, .x: .x, .y: .y,
        .up: .up, .down: .down, .left: .left, .right: .right,
        .l: .leftTrigger, .r: .rightTrigger, .zl: .zl, .zr: .zr,
        .plus: .start, .minus: .select, .home: .home
    ]
}
#endif
