import EmulationKit
import Foundation
import QuartzCore
import UIKit
import XCTest
@testable import Tandem

final class SessionTests: XCTestCase {
    @MainActor
    func testStartingWaitsForNativeInitialization() async throws {
        let (session, core, game) = try makeSession()
        var didStartCount = 0
        session.didStart = { _ in didStartCount += 1 }
        XCTAssertEqual(session.state, .starting)
        XCTAssertEqual(session.game, game)

        var attached = false
        let attachTask = Task {
            await attach(session)
            attached = true
        }
        defer { core.finishStart(); attachTask.cancel() }
        guard await waitFor({ core.startCalls == 1 }, "Core start was not entered") else { return }
        XCTAssertEqual(session.state, .starting)
        XCTAssertFalse(attached)
        XCTAssertEqual(didStartCount, 0)

        core.finishStart()
        guard await waitFor({ session.state == .running && attached }, "Session did not finish starting") else { return }
        XCTAssertEqual(didStartCount, 1)

        var stopped = false
        let stopTask = Task { await session.stop(); stopped = true }
        defer { stopTask.cancel() }
        guard await waitFor({ stopped }, "Session did not stop") else { return }
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(core.stopCalls, 1)
    }

    @MainActor
    func testStopDuringPendingStartWaitsThenReturnsToIdle() async throws {
        let (session, core, _) = try makeSession()
        var didStartCount = 0
        session.didStart = { _ in didStartCount += 1 }
        var attached = false
        let attachTask = Task { await attach(session); attached = true }
        defer { core.finishStart(); attachTask.cancel() }
        guard await waitFor({ core.startCalls == 1 }, "Core start was not entered") else { return }

        var stopped = false
        let stopTask = Task { await session.stop(); stopped = true }
        defer { stopTask.cancel() }
        guard await waitFor({ session.state == .stopping }, "Stop did not begin") else { return }
        XCTAssertFalse(stopped)
        XCTAssertEqual(core.stopCalls, 0, "Native teardown must wait for initialization to return")

        core.finishStart()
        guard await waitFor({ stopped && attached }, "Pending start and stop did not complete") else { return }
        XCTAssertEqual(session.state, .idle)
        XCTAssertNil(session.game)
        XCTAssertEqual(core.stopCalls, 1)
        XCTAssertEqual(didStartCount, 0, "A cancelled launch must not report a started session")
    }

    @MainActor
    func testSuspendedPauseCannotRestorePausedStateAfterStop() async throws {
        try await checkSuspendedPauseCannotOverrideStop(paused: true)
    }

    @MainActor
    func testSuspendedResumeCannotRestoreRunningStateAfterStop() async throws {
        try await checkSuspendedPauseCannotOverrideStop(paused: false)
    }

    @MainActor
    private func checkSuspendedPauseCannotOverrideStop(paused: Bool) async throws {
        let (session, core, _) = try makeSession()
        let attachTask = Task { await attach(session) }
        defer { core.finishStart(); core.finishPause(); attachTask.cancel() }
        guard await waitFor({ core.startCalls == 1 }, "Core start was not entered") else { return }
        core.finishStart()
        guard await waitFor({ session.state == .running }, "Session did not start") else { return }

        if !paused {
            await session.setPaused(true)
            XCTAssertEqual(session.state, .paused)
        }
        let priorRequests = core.pauseRequests.count
        core.blocksPause = true
        var pauseFinished = false
        let pauseTask = Task { await session.setPaused(paused); pauseFinished = true }
        defer { core.finishPause(); pauseTask.cancel() }
        guard await waitFor({ core.pauseRequests.count == priorRequests + 1 }, "Pause/resume did not enter the core") else { return }
        XCTAssertEqual(core.pauseRequests.last, paused)
        XCTAssertFalse(pauseFinished)

        var stopped = false
        let stopTask = Task { await session.stop(); stopped = true }
        defer { stopTask.cancel() }
        guard await waitFor({ stopped }, "Stop was blocked by an outstanding pause/resume") else { return }
        XCTAssertEqual(session.state, .idle)
        XCTAssertNil(session.game)

        core.finishPause()
        guard await waitFor({ pauseFinished }, "Suspended pause/resume did not return") else { return }
        XCTAssertEqual(session.state, .idle, "A late native completion must not overwrite the stopped session")
        XCTAssertNil(session.game)
        XCTAssertEqual(core.stopCalls, 1)
    }

    @MainActor
    func testSaveStatesPauseAndReportFailureWithoutEndingSession() async throws {
        let (session, core, _) = try makeSession()
        core.finishStart()
        await attach(session)
        XCTAssertEqual(session.state, .running)
        await session.writeSaveState(slot: 1)
        XCTAssertEqual(session.state, .paused)
        XCTAssertEqual(core.savedSlots, [1])
        XCTAssertEqual(session.saveSlots.first?.id, 1)
        XCTAssertFalse(session.isStateBusy)
        core.stateFailure = true
        await session.restoreSaveState(slot: 1)
        XCTAssertNotNil(session.saveStateMessage)
        XCTAssertEqual(session.state, .paused)
        XCTAssertFalse(session.isStateBusy)
        await session.stop()
        XCTAssertTrue(session.saveSlots.isEmpty)
    }


    func testPlayerSettingsRoundTripAndSanitizeInvalidValues() {
        let portrait = PlayerConfiguration.defaults(landscape: false)
        let landscape = PlayerConfiguration.defaults(landscape: true)
        XCTAssertEqual(portrait.layout, .stacked)
        XCTAssertEqual(landscape.layout, .sideBySide)
        XCTAssertEqual(PlayerConfiguration.decode(portrait.serialized, landscape: false), portrait)
        XCTAssertEqual(PlayerConfiguration.decode(landscape.serialized, landscape: true), landscape)
        XCTAssertEqual(PlayerConfiguration.decode("damaged", landscape: true), landscape)
        var edited = portrait
        edited.controlOpacity = -1
        edited.controlScale = 100
        edited.screenScale = .nan
        edited.left.x = -1
        let restored = PlayerConfiguration.decode(edited.serialized, landscape: false)
        XCTAssertEqual(restored.controlOpacity, 0.25)
        XCTAssertEqual(restored.controlScale, 1.15)
        XCTAssertEqual(restored.screenScale, 1)
        XCTAssertEqual(restored.left.x, 0)
        XCTAssertEqual(portrait.layout, .stacked)
    }

    func testScreenLayoutsKeepBothAspectRatiosInsideBounds() {
        for size in [CGSize(width: 320, height: 480), CGSize(width: 800, height: 240), CGSize(width: 1, height: 1)] {
            let bounds = CGRect(origin: .zero, size: size)
            for layout in PlayerScreenLayout.allCases {
                var config = PlayerConfiguration()
                config.layout = layout
                config.screenGap = 32
                config.screenScale = 0.65
                let frames = PlayerScreenFrames.calculate(in: bounds, configuration: config)
                XCTAssertTrue(bounds.insetBy(dx: -0.001, dy: -0.001).contains(frames.primary))
                XCTAssertTrue(bounds.insetBy(dx: -0.001, dy: -0.001).contains(frames.secondary))
                XCTAssertEqual(frames.primary.width / frames.primary.height, 400.0 / 240.0, accuracy: 0.001)
                XCTAssertEqual(frames.secondary.width / frames.secondary.height, 320.0 / 240.0, accuracy: 0.001)
                XCTAssertFalse(frames.primary.intersects(frames.secondary))
            }
        }
        let empty = PlayerScreenFrames.calculate(in: .zero, configuration: PlayerConfiguration())
        XCTAssertEqual(empty.primary, .zero)
        XCTAssertEqual(empty.secondary, .zero)
    }

    func testControlPlacementStaysInsideThePlayer() {
        let bounds = CGRect(x: 10, y: 20, width: 300, height: 200)
        let size = CGSize(width: 100, height: 80)
        for anchor in [ControlAnchor(x: 0, y: 0), ControlAnchor(x: 1, y: 1)] {
            let center = PlayerScreenFrames.controlCenter(anchor, size: size, in: bounds)
            XCTAssertTrue(bounds.contains(CGRect(x: center.x - 50, y: center.y - 40, width: 100, height: 80)))
        }
    }

    @MainActor
    func testChangingOnlyTheTouchScreenSizeNotifiesCoreWithoutReplacingLayers() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1200, height: 240))
        var config = PlayerConfiguration()
        config.layout = .sideBySide
        let view = ScreenPairView(dualScreen: true, configuration: config)
        view.frame = window.bounds
        var attaches = 0
        view.onAttach = { _, _ in attaches += 1 }
        window.addSubview(view)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let topLayer = view.primary.metalLayer
        let touchLayer = view.secondary.metalLayer
        let topSize = topLayer.drawableSize
        let oldTouchSize = touchLayer.drawableSize
        let previousAttaches = attaches
        config.layout = .topFocus
        view.configuration = config
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertTrue(view.primary.metalLayer === topLayer)
        XCTAssertTrue(view.secondary.metalLayer === touchLayer)
        XCTAssertEqual(view.primary.metalLayer.drawableSize, topSize)
        XCTAssertLessThan(view.secondary.metalLayer.drawableSize.width, oldTouchSize.width)
        XCTAssertGreaterThan(attaches, previousAttaches)
        XCTAssertFalse(view.primary.isUserInteractionEnabled)
        XCTAssertTrue(view.secondary.isUserInteractionEnabled)
    }

    @MainActor
    private func makeSession() throws -> (EmulationSession, SuspendedCore, GameRecord) {
        let core = SuspendedCore()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = EmulationSession(systemDirectory: directory, coreFactory: { system in
            XCTAssertEqual(system, .nintendo3DS)
            return core
        })
        let id = UUID()
        let game = GameRecord(id: id, title: "Lifecycle test", system: .nintendo3DS,
                              relativePath: "ROMs/\(id.uuidString).3dsx", byteCount: 4)
        try session.prepare(game, fileURL: directory.appendingPathComponent("test.3dsx"))
        return (session, core, game)
    }

    @MainActor
    private func attach(_ session: EmulationSession) async {
        let primary = CAMetalLayer()
        primary.drawableSize = CGSize(width: 400, height: 240)
        let secondary = CAMetalLayer()
        secondary.drawableSize = CGSize(width: 320, height: 240)
        await session.attach(primary: primary, secondary: secondary)
    }

    /// Every wait is bounded, so a regression reports a failure instead of
    /// leaving XCTest waiting forever on the deliberately suspended core.
    @MainActor
    private func waitFor(
        _ condition: @MainActor () -> Bool,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> Bool {
        for _ in 0..<1_000 {
            if condition() { return true }
            await Task.yield()
        }
        XCTFail(message, file: file, line: line)
        return false
    }
}

@MainActor
private final class SuspendedCore: EmulatorCore, SaveStateCore {
    var savedSlots: [Int] = []
    var stateFailure = false
    func saveStateSlots() async throws -> [SaveStateSlot] {
        [SaveStateSlot(id: 1, savedAt: Date(), compatible: true)]
    }
    func saveState(slot: Int) async throws { savedSlots.append(slot) }
    func loadState(slot: Int) async throws {
        if stateFailure { throw EmulationError.startFailed("Incompatible state") }
    }
    let system = GameSystem.nintendo3DS
    let name = "Suspended test core"
    private(set) var startCalls = 0
    private(set) var stopCalls = 0
    private(set) var pauseRequests: [Bool] = []
    var blocksPause = false
    private var startReleased = false
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var pauseContinuation: CheckedContinuation<Void, Never>?

    func start(gameURL: URL, surfaces: RenderSurfaces, systemDirectory: URL) async throws {
        startCalls += 1
        guard !startReleased else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            startContinuation = continuation
        }
    }

    func finishStart() {
        startReleased = true
        let continuation = startContinuation
        startContinuation = nil
        continuation?.resume(returning: ())
    }

    func setPaused(_ paused: Bool) async {
        pauseRequests.append(paused)
        if blocksPause {
            await withCheckedContinuation { continuation in pauseContinuation = continuation }
        }
    }

    func finishPause() {
        blocksPause = false
        let continuation = pauseContinuation
        pauseContinuation = nil
        continuation?.resume()
    }

    func stop() async { stopCalls += 1 }
    func setButton(_ button: EmulatorButton, pressed: Bool) {}
    func setStick(_ stick: EmulatorStick, x: Float, y: Float) {}
    func touch(_ phase: TouchPhase, x: Float, y: Float) {}
}
