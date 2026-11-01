import Foundation

struct SaveStateSlot: Identifiable, Equatable {
    let id: Int
    let savedAt: Date?
    let compatible: Bool
}

@MainActor
protocol SaveStateCore: AnyObject {
    func saveStateSlots() async throws -> [SaveStateSlot]
    func saveState(slot: Int) async throws
    func loadState(slot: Int) async throws
}
