import Combine
import Foundation
import QuartzCore
import AVFoundation
import EmulationKit

enum SessionState: Equatable {
    case idle, starting, running, paused, stopping, failed(String)
}

@MainActor
final class EmulationSession: ObservableObject {
    @Published private(set) var state: SessionState = .idle
    @Published private(set) var game: GameRecord?
    var coreName: String { core?.name ?? "No core loaded" }
    var canPause: Bool { state == .running || state == .paused }

    @Published private(set) var saveSlots: [SaveStateSlot] = []
    @Published private(set) var isStateBusy = false
    @Published var saveStateMessage: String?
    var supportsSaveStates: Bool { core is any SaveStateCore }

    func refreshSaveStates() async {
        await performStateAction { core in try await core.saveStateSlots() }
    }

    func writeSaveState(slot: Int) async {
        await performStateAction { core in
            try await core.saveState(slot: slot)
            return try await core.saveStateSlots()
        }
    }

    func restoreSaveState(slot: Int) async {
        await performStateAction { core in
            try await core.loadState(slot: slot)
            return try await core.saveStateSlots()
        }
    }

    private func performStateAction(_ operation: (any SaveStateCore) async throws -> [SaveStateSlot]) async {
        guard canPause, !isStateBusy, let core = core as? any SaveStateCore else { return }
        let token = generation
        isStateBusy = true
        saveStateMessage = nil
        defer { if token == generation { isStateBusy = false } }
        await setPaused(true)
        guard token == generation, state == .paused else { return }
        do {
            let slots = try await operation(core)
            guard token == generation else { return }
            saveSlots = slots
        } catch {
            guard token == generation else { return }
            saveStateMessage = error.localizedDescription
        }
    }

    private var core: (any EmulatorCore)?
    private var gameURL: URL?
    private let systemDirectory: URL
    private let coreFactory: @MainActor (GameSystem) throws -> any EmulatorCore
    private var surfaces: RenderSurfaces?
    private var launchTask: Task<Void, Never>?
    private var generation = UUID()
    private var pauseRequest = UUID()
    private var heldButtons: Set<EmulatorButton> = []
    private lazy var controllers = ControllerInput(session: self)
    var didStart: ((GameRecord) -> Void)?

    init(systemDirectory: URL,
         coreFactory: @MainActor @escaping (GameSystem) throws -> any EmulatorCore = { try CoreRegistry.makeCore(for: $0) }) {
        self.systemDirectory = systemDirectory
        self.coreFactory = coreFactory
    }

    func prepare(_ game: GameRecord, fileURL: URL) throws {
        guard self.game == nil else { return }
        core = try coreFactory(game.system)
        generation = UUID()
        let token = generation
        if let reporting = core as? any CoreExitReporting {
            reporting.onUnexpectedExit = { [weak self] message in
                guard let self, generation == token, canPause else { return }
                controllers.disconnect()
                releaseInputs()
                state = .failed(message)
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
        gameURL = fileURL
        self.game = game
        state = .starting
    }

    func attach(primary: CAMetalLayer, secondary: CAMetalLayer?) async {
        if state == .running || state == .paused {
            let updated = RenderSurfaces(primary: primary, secondary: secondary)
            surfaces = updated
            await core?.resize(surfaces: updated)
            return
        }
        guard state == .starting, launchTask == nil, let core, let gameURL else { return }
        guard primary.drawableSize.width > 0, primary.drawableSize.height > 0 else { return }
        if game?.system == .nintendo3DS, secondary == nil { return }
        let surfaces = RenderSurfaces(primary: primary, secondary: secondary)
        self.surfaces = surfaces
        let token = generation
        launchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                try await core.start(gameURL: gameURL, surfaces: surfaces, systemDirectory: systemDirectory)
                guard token == generation, !Task.isCancelled else { return }
                // A rotation can change drawable size while native startup is
                // suspended. Apply its current size before accepting input.
                await core.resize(surfaces: self.surfaces ?? surfaces)
                guard token == generation, !Task.isCancelled else { return }
                controllers.connect()
                state = .running
                if let game { didStart?(game) }
            } catch {
                guard token == generation else { return }
                await core.stop()
                guard token == generation else { return }
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                state = .failed(error.localizedDescription)
            }
        }
        await launchTask?.value
    }

    func setPaused(_ paused: Bool) async {
        guard canPause else { return }
        let token = generation
        let request = UUID()
        pauseRequest = request
        if paused { releaseInputs() }
        if paused { state = .paused }
        await core?.setPaused(paused)
        guard token == generation, pauseRequest == request,
              state != .idle, state != .stopping else { return }
        state = paused ? .paused : .running
    }

    func stop() async {
        guard state != .idle, state != .stopping else { return }
        state = .stopping
        isStateBusy = false
        saveSlots = []
        saveStateMessage = nil
        generation = UUID()
        launchTask?.cancel()
        // Wait for native initialization before teardown, avoiding use-after-free.
        await launchTask?.value
        launchTask = nil
        controllers.disconnect()
        releaseInputs()
        await core?.stop()
        core = nil
        surfaces = nil
        gameURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        game = nil
        state = .idle
    }

    func setButton(_ button: EmulatorButton, pressed: Bool) {
        guard state == .running else { return }
        if pressed { heldButtons.insert(button) } else { heldButtons.remove(button) }
        core?.setButton(button, pressed: pressed)
    }

    func setStick(_ stick: EmulatorStick, x: Float, y: Float) {
        guard state == .running else { return }
        core?.setStick(stick, x: max(-1, min(1, x)), y: max(-1, min(1, y)))
    }

    func touch(_ phase: TouchPhase, x: Float, y: Float) {
        guard state == .running else { return }
        core?.touch(phase, x: max(0, min(1, x)), y: max(0, min(1, y)))
    }

    private func releaseInputs() {
        for button in heldButtons { core?.setButton(button, pressed: false) }
        heldButtons.removeAll()
        core?.setStick(.left, x: 0, y: 0)
        core?.setStick(.right, x: 0, y: 0)
        core?.touch(.ended, x: 0, y: 0)
    }
}
