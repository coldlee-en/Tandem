import Foundation
import EmulationKit

@MainActor
enum CoreRegistry {
    static func availability(for system: GameSystem) -> CoreAvailability {
#if targetEnvironment(simulator)
        return CoreAvailability(isAvailable: false, summary: "Physical device required",
            detail: "The simulator supports the library and controls. Native emulation is configured for an arm64 iPhone or iPad.")
#else
        switch system {
        case .nintendo3DS:
#if canImport(Cytrus)
            return CoreAvailability(isAvailable: true,
                summary: TandemIsJITEnabled() ? "Cytrus linked · JIT available" : "Cytrus linked · interpreter mode",
                detail: "Azahar-based core with dual screens. Native gameplay is experimental and unverified in this build environment.")
#else
            return CoreAvailability(isAvailable: false, summary: "3DS core not linked",
                detail: "Run scripts/prepare_3ds.sh, generate the native project, and build on a Mac. The standard project contains the library and controller interface.")
#endif
        case .nintendoSwitch:
            guard SwitchCore.isBundled else {
                return CoreAvailability(isAvailable: false, summary: "Switch core not embedded",
                    detail: "Build the pinned MeloNX native core using scripts/build_switch.sh, then generate the native project to embed its signed dependencies.")
            }
            guard TandemIsJITEnabled() else {
                return CoreAvailability(isAvailable: false, summary: "Switch requires JIT",
                    detail: "Attach Xcode's debugger to this development build. Your console's required keys and firmware must be present in System/Switch.")
            }
            return CoreAvailability(isAvailable: true, summary: "MeloNX embedded · JIT available",
                detail: "Experimental Ryujinx-based core. Startup is confirmed only after the core renders its first frame. Game compatibility varies.")
        }
#endif
    }

    static func makeCore(for system: GameSystem) throws -> any EmulatorCore {
        let status = availability(for: system)
        guard status.isAvailable else { throw EmulationError.unavailable(status.summary + ". " + status.detail) }
        switch system {
        case .nintendo3DS:
#if canImport(Cytrus)
            return CytrusCore()
#else
            throw EmulationError.unavailable(status.detail)
#endif
        case .nintendoSwitch:
            return SwitchCore()
        }
    }
}
