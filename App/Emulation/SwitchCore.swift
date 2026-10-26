import Darwin
import Foundation
import QuartzCore
import EmulationKit

private final class SwitchEventRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (String) -> Void)?

    func setHandler(_ handler: (@Sendable (String) -> Void)?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func deliver(_ event: String) {
        lock.lock()
        let current = handler
        lock.unlock()
        current?(event)
    }
}

private let switchEvents = SwitchEventRouter()

/// MeloNX's NativeAOT headless API, pinned by scripts/build_switch.sh.
/// NativeAOT runtimes are process resident: loaded handles are never dlclosed.
private final class SwitchNativeLibrary: @unchecked Sendable {
    typealias Event = @convention(c) (UnsafePointer<CChar>?) -> Void
    typealias Register = @convention(c) (Event?) -> Void
    typealias Initialize = @convention(c) () -> Void
    typealias InitializeJIT = @convention(c) () -> UInt8
    typealias Main = @convention(c) (Int32, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
    typealias Window = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias Attach = @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    typealias Detach = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias Button = @convention(c) (UnsafeMutableRawPointer?, Int32, UInt8) -> Void
    typealias Stick = @convention(c) (UnsafeMutableRawPointer?, Int32, Float, Float) -> Void
    typealias Pause = @convention(c) (UInt8) -> Void
    typealias ViewSize = @convention(c) (Int32, Int32) -> Void
    typealias Touch = @convention(c) (Float, Float, Int32) -> Void
    typealias TouchEnd = @convention(c) (Int32) -> Void
    typealias InstallFirmware = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    typealias FreeString = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    let initialize: InitializeJIT
    let initializeJIT: InitializeJIT
    let run: Main
    let setWindow: Window
    let attach: Attach
    let detach: Detach
    let button: Button
    let stick: Stick
    let pause: Pause
    let stop: Initialize
    let register: Register
    let viewSize: ViewSize
    let touchBegan: Touch
    let touchMoved: Touch
    let touchEnded: TouchEnd
    let installFirmware: InstallFirmware
    let freeString: FreeString

    static var executableURL: URL? {
        Bundle.main.privateFrameworksURL?.appendingPathComponent("Ryujinx.Headless.SDL2.dylib")
    }

    static var isBundled: Bool {
        guard let url = executableURL,
              let file = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? file.close() }
        guard let prefix = try? file.read(upToCount: 4), prefix.count == 4 else { return false }
        // arm64 Mach-O or a universal binary; reject Git LFS pointer text.
        let headers: [[UInt8]] = [[0xcf, 0xfa, 0xed, 0xfe], [0xca, 0xfe, 0xba, 0xbe],
                                   [0xca, 0xfe, 0xba, 0xbf]]
        return headers.contains(Array(prefix))
    }

    init() throws {
        guard Self.isBundled, let executable = Self.executableURL,
              let frameworks = Bundle.main.privateFrameworksURL else {
            throw EmulationError.unavailable("Build and embed the MeloNX Switch core using scripts/build_switch.sh on a Mac first.")
        }
        let helperPath = frameworks.appendingPathComponent("RyujinxHelper.framework/RyujinxHelper").path
        guard let helper = dlopen(helperPath, RTLD_NOW | RTLD_GLOBAL) else {
            throw EmulationError.startFailed("Cannot load RyujinxHelper: \(Self.loaderError())")
        }
        guard let handle = dlopen(executable.path, RTLD_NOW | RTLD_GLOBAL) else {
            throw EmulationError.startFailed("Cannot load the Switch core: \(Self.loaderError())")
        }
        func symbol<T>(_ name: String, from library: UnsafeMutableRawPointer, as type: T.Type) throws -> T {
            guard let pointer = dlsym(library, name) else {
                throw EmulationError.startFailed("The Switch core is missing \(name). Rebuild the pinned core and helper together.")
            }
            return unsafeBitCast(pointer, to: type)
        }
        initialize = try symbol("tandem_initialize", from: handle, as: InitializeJIT.self)
        initializeJIT = try symbol("tandem_initialize_jit", from: handle, as: InitializeJIT.self)
        run = try symbol("main_ryujinx_sdl", from: handle, as: Main.self)
        setWindow = try symbol("set_native_window", from: handle, as: Window.self)
        attach = try symbol("attach_gamepad", from: handle, as: Attach.self)
        detach = try symbol("detach_gamepad", from: handle, as: Detach.self)
        button = try symbol("set_gamepad_button_state", from: handle, as: Button.self)
        stick = try symbol("set_gamepad_stick_axis", from: handle, as: Stick.self)
        pause = try symbol("pause_emulation", from: handle, as: Pause.self)
        stop = try symbol("stop_emulation", from: handle, as: Initialize.self)
        register = try symbol("TandemRegisterEventCallback", from: helper, as: Register.self)
        viewSize = try symbol("set_view_size", from: handle, as: ViewSize.self)
        touchBegan = try symbol("touch_began", from: handle, as: Touch.self)
        touchMoved = try symbol("touch_moved", from: handle, as: Touch.self)
        touchEnded = try symbol("touch_ended", from: handle, as: TouchEnd.self)
        installFirmware = try symbol("install_firmware", from: handle, as: InstallFirmware.self)
        freeString = try symbol("free_firmware_version", from: handle, as: FreeString.self)
    }

    private static func loaderError() -> String {
        dlerror().map { String(cString: $0) } ?? "unknown loader error"
    }
}

/// Owns the opaque controller ID until the native run exits.
private final class SwitchNativeJob: @unchecked Sendable {
    let controllerID = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    deinit {
        controllerID.deallocate()
    }

    var inputID: String { String(UInt(bitPattern: controllerID), radix: 16, uppercase: true) }
}

@MainActor
final class SwitchCore: EmulatorCore, CoreExitReporting {
    let system = GameSystem.nintendoSwitch
    let name = "MeloNX · Ryujinx"
    static var isBundled: Bool { SwitchNativeLibrary.isBundled }
    var onUnexpectedExit: ((String) -> Void)?

    private static weak var active: SwitchCore?
    private static var residentLibrary: SwitchNativeLibrary?
    private static var maintenanceBusy = false
    private var library: SwitchNativeLibrary?
    private var job: SwitchNativeJob?
    private var worker: Thread?
    private var surfaces: RenderSurfaces?
    private var launch: CheckedContinuation<Void, Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var timeoutTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var stopping = false
    private var ready = false
    private var operation = UUID()

    /// Firmware parsing/installing uses NativeAOT code and does not run the guest CPU.
    /// Keep the external file accessible until the synchronous native install ends.
    static func installFirmware(from url: URL, systemDirectory: URL) async throws -> String {
        guard active == nil, !maintenanceBusy else {
            throw EmulationError.startFailed("Close the Switch game or wait for the current firmware installation to finish.")
        }
        maintenanceBusy = true
        defer { maintenanceBusy = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard url.isFileURL, url.pathExtension.lowercased() == "zip" else {
            throw EmulationError.startFailed("Select a nonempty Switch firmware ZIP file.")
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
            throw EmulationError.startFailed("Select a nonempty Switch firmware ZIP file.")
        }
        let root = systemDirectory.appendingPathComponent("Switch", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard setenv("TANDEM_SWITCH_ROOT", root.path, 1) == 0 else {
            throw EmulationError.startFailed("Cannot configure the Switch system directory.")
        }
        let native: SwitchNativeLibrary
        if let resident = residentLibrary { native = resident }
        else {
            native = try SwitchNativeLibrary()
            residentLibrary = native
        }
        try Task.checkCancellation()
        // The Tandem patch keeps InstallFirmware synchronous so completion means
        // the NAND write has actually finished, rather than merely been queued.
        return try await Task.detached(priority: .userInitiated) {
            guard native.initialize() != 0 else {
                throw EmulationError.startFailed("Cannot initialize the Switch system data. Check your console keys and the core log.")
            }
            guard let result = url.path.withCString({ native.installFirmware($0) }) else {
                throw EmulationError.startFailed("The Switch core returned no firmware installation result.")
            }
            defer { native.freeString(result) }
            let version = String(cString: result).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !version.isEmpty, !version.contains("✖"), !version.lowercased().hasPrefix("error") else {
                throw EmulationError.startFailed(version.isEmpty ? "The firmware package could not be installed." : version)
            }
            return version
        }.value
    }

    func start(gameURL: URL, surfaces: RenderSurfaces, systemDirectory: URL) async throws {
        guard worker == nil, Self.active == nil, !Self.maintenanceBusy else {
            throw EmulationError.startFailed("A Switch session or firmware installation is already active.")
        }
        guard TandemIsJITEnabled() else { throw EmulationError.jitRequired }
        guard surfaces.primary.drawableSize.width > 0, surfaces.primary.drawableSize.height > 0 else {
            throw EmulationError.invalidSurface
        }
        let root = systemDirectory.appendingPathComponent("Switch", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // scripts/patch_switch.py makes initialize() respect this before VFS setup.
        guard setenv("TANDEM_SWITCH_ROOT", root.path, 1) == 0 else {
            throw EmulationError.startFailed("Cannot configure the Switch system directory.")
        }
        let native: SwitchNativeLibrary
        if let resident = Self.residentLibrary { native = resident }
        else {
            native = try SwitchNativeLibrary()
            Self.residentLibrary = native
        }
        let owned = SwitchNativeJob()
        let arguments = [gameURL.path, "--root-data-dir", root.path,
                         "--graphics-backend", "Vulkan", "--memory-manager-mode", "HostMappedUnsafe",
                         "--resolution-scale", "1", "--disable-docked-mode", "--disable-shader-cache",
                         "--input-id-handheld", owned.inputID, "--correct-controller",
                         "--exclusive-fullscreen",
                         "--exclusive-fullscreen-width", String(Int(surfaces.primary.drawableSize.width)),
                         "--exclusive-fullscreen-height", String(Int(surfaces.primary.drawableSize.height))]
        // The pointer value is the controller ID in the native gamepad driver.
        let invocation = try SwitchInvocation(job: owned, arguments: arguments)
        self.library = native
        self.job = owned
        self.surfaces = surfaces
        self.stopping = false
        self.ready = false
        operation = UUID()
        let token = operation
        Self.active = self
        switchEvents.setHandler { [weak self] event in
            Task { @MainActor in
                guard let self, self.operation == token else { return }
                self.receive(event)
            }
        }
        native.register { identifier in
            guard let identifier else { return }
            switchEvents.deliver(String(cString: identifier))
        }
        native.setWindow(Unmanaged.passUnretained(surfaces.primary).toOpaque())

        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                launch = continuation
                let thread = Thread { [weak self] in
                    guard native.initialize() != 0 else {
                        Task { @MainActor in self?.finished(token: token, status: -4) }
                        return
                    }
                    guard native.initializeJIT() != 0 else {
                        Task { @MainActor in self?.finished(token: token, status: -2) }
                        return
                    }
                    let attached = "Tandem Controller".withCString { native.attach($0, owned.controllerID) }
                    guard attached != nil else {
                        Task { @MainActor in self?.finished(token: token, status: -3) }
                        return
                    }
                    let result = invocation.run(native)
                    native.detach(owned.controllerID)
                    Task { @MainActor in self?.finished(token: token, status: result) }
                }
                thread.name = "Tandem.Switch"
                thread.qualityOfService = .userInteractive
                worker = thread
                thread.start()
                timeoutTask = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 90_000_000_000) } catch { return }
                    guard let self, operation == token, !ready else { return }
                    requestStop(error: EmulationError.startFailed("The Switch core did not render a frame within 90 seconds. Check your system data and the core log before trying again."))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, operation == token else { return }
                requestStop(error: CancellationError())
            }
        }
    }

    func resize(surfaces: RenderSurfaces) async {
        self.surfaces = surfaces
        library?.setWindow(Unmanaged.passUnretained(surfaces.primary).toOpaque())
        library?.viewSize(Int32(surfaces.primary.drawableSize.width), Int32(surfaces.primary.drawableSize.height))
    }

    func setPaused(_ paused: Bool) async {
        guard ready, !stopping else { return }
        library?.pause(paused ? 1 : 0)
    }

    func stop() async {
        guard worker != nil else { cleanup(); return }
        requestStop(error: CancellationError())
        // Do not release Metal layers or argv while native threads still use them.
        await withCheckedContinuation { waiters.append($0) }
    }

    private func receive(_ event: String) {
        guard event == "ran-first-frame", worker != nil, !stopping else { return }
        ready = true
        timeoutTask?.cancel()
        timeoutTask = nil
        let continuation = launch
        launch = nil
        continuation?.resume()
    }

    private func requestStop(error: Error) {
        guard worker != nil else { return }
        stopping = true
        ready = false
        timeoutTask?.cancel()
        timeoutTask = nil
        let continuation = launch
        launch = nil
        continuation?.resume(throwing: error)
        guard stopTask == nil else { return }
        // Upstream stop is a no-op until its window exists. Retry during startup.
        stopTask = Task { [weak self] in
            while let self, worker != nil {
                library?.stop()
                do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
            }
        }
    }

    private func finished(token: UUID, status: Int32) {
        guard token == operation else { return }
        let exitedDuringPlay = ready && !stopping
        let continuation = launch
        launch = nil
        if let continuation {
            let message = status == -4 ? "The Switch core could not initialize its system data. Check the Switch core log and your console data."
                : status == -2 ? "The Switch core could not initialize dual-mapped JIT. Attach Xcode's debugger and relaunch."
                : status == -3 ? "The Switch core could not attach its controller."
                : "The Switch core exited before rendering a frame (status \(status)). Check your firmware, keys, game format, and the core log."
            continuation.resume(throwing: EmulationError.startFailed(message))
        }
        cleanup()
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
        if exitedDuringPlay {
            onUnexpectedExit?("The Switch core stopped (status \(status)). Review the core log and your game and console data before relaunching.")
        }
    }

    private func cleanup() {
        timeoutTask?.cancel()
        timeoutTask = nil
        stopTask?.cancel()
        stopTask = nil
        if Self.active === self {
            switchEvents.setHandler(nil)
            library?.register(nil)
            library?.touchEnded(0)
            library?.setWindow(nil)
            Self.active = nil
        }
        worker = nil
        job = nil
        surfaces = nil
        ready = false
        stopping = false
    }

    func setButton(_ button: EmulatorButton, pressed: Bool) {
        guard ready, !stopping, let job, let code = Self.buttons[button] else { return }
        library?.button(job.controllerID, code, pressed ? 1 : 0)
    }

    func setStick(_ stick: EmulatorStick, x: Float, y: Float) {
        guard ready, !stopping, let job else { return }
        library?.stick(job.controllerID, stick == .left ? 1 : 2, x, y)
    }

    func touch(_ phase: TouchPhase, x: Float, y: Float) {
        guard ready, !stopping, let layer = surfaces?.primary else { return }
        let pointX = x * Float(layer.drawableSize.width)
        let pointY = y * Float(layer.drawableSize.height)
        switch phase {
        case .began: library?.touchBegan(pointX, pointY, 0)
        case .moved: library?.touchMoved(pointX, pointY, 0)
        case .ended: library?.touchEnded(0)
        }
    }

    private static let buttons: [EmulatorButton: Int32] = [
        .a: 0, .b: 1, .x: 2, .y: 3, .minus: 4, .home: 5, .plus: 6,
        .lStick: 7, .rStick: 8, .l: 9, .r: 10,
        .up: 11, .down: 12, .left: 13, .right: 14, .zl: 15, .zr: 16
    ]
}

private final class SwitchInvocation: @unchecked Sendable {
    let job: SwitchNativeJob
    private let arguments: [UnsafeMutablePointer<CChar>?]

    init(job: SwitchNativeJob, arguments: [String]) throws {
        self.job = job
        var owned: [UnsafeMutablePointer<CChar>?] = []
        for argument in arguments {
            guard let pointer = strdup(argument) else {
                owned.forEach { free($0) }
                throw EmulationError.startFailed("Insufficient memory to prepare the Switch core.")
            }
            owned.append(pointer)
        }
        self.arguments = owned
    }

    deinit { arguments.forEach { free($0) } }

    func run(_ native: SwitchNativeLibrary) -> Int32 {
        var argv = arguments + [nil]
        return argv.withUnsafeMutableBufferPointer { native.run(Int32(arguments.count), $0.baseAddress) }
    }
}
