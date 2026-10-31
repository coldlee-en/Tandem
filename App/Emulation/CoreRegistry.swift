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
            return CoreAvailability(isAvailable: false, summary: "Switch support removed", detail: "Existing files remain on this device.")
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
            throw EmulationError.unavailable("Switch support has been removed. Existing files remain on this device.")
        }
    }
}
