import SwiftUI

@MainActor
struct SaveStatesView: View {
    @ObservedObject var session: EmulationSession
    @Environment(\.dismiss) private var dismiss
    @State private var pendingAction: SlotAction?
    @State private var completed: String?

    private struct SlotAction: Identifiable {
        let slot: Int
        let loading: Bool
        var id: String { "\(slot)-\(loading)" }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("The game stays paused while you manage states. In-game saves are separate. Save states may stop working after core updates.")
                        .font(.footnote).foregroundStyle(TandemTheme.muted)
                }
                Section("Save slots") {
                    ForEach(session.saveSlots) { slot in
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Slot \(slot.id)").font(.headline)
                            if let date = slot.savedAt {
                                Text(date, format: .dateTime.month().day().hour().minute())
                                    .font(.subheadline).foregroundStyle(TandemTheme.muted)
                                if !slot.compatible {
                                    Text("Incompatible state — save here to replace it.").font(.caption).foregroundStyle(.orange)
                                }
                            } else { Text("Empty").foregroundStyle(TandemTheme.muted) }
                            HStack(spacing: 24) {
                                Button("Save", systemImage: "square.and.arrow.down") {
                                    if slot.savedAt != nil { pendingAction = SlotAction(slot: slot.id, loading: false) }
                                    else { run(SlotAction(slot: slot.id, loading: false)) }
                                }
                                Button("Load", systemImage: "arrow.counterclockwise") {
                                    pendingAction = SlotAction(slot: slot.id, loading: true)
                                }.disabled(slot.savedAt == nil || !slot.compatible)
                            }.buttonStyle(.bordered)
                        }.padding(.vertical, 8)
                    }
                }.disabled(session.isStateBusy || !session.canPause)
                if session.isStateBusy { ProgressView("Working…") }
                if let message = session.saveStateMessage {
                    Section { Text(message).foregroundStyle(.red) }
                }
                if let completed { Section { Text(completed).foregroundStyle(TandemTheme.mint) } }
            }
            .scrollContentBackground(.hidden).background(TandemTheme.background)
            .navigationTitle("Save states").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() }.disabled(session.isStateBusy) }
            .confirmationDialog(pendingAction?.loading == true ? "Load this state?" : "Replace this save state?", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }), titleVisibility: .visible) {
                if let action = pendingAction {
                    Button(action.loading ? "Load state" : "Replace state", role: .destructive) { run(action) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Loading discards your current unsaved progress. Saving replaces only the selected state slot.") }
        }
        .tint(TandemTheme.mint).interactiveDismissDisabled(session.isStateBusy)
        .task { await session.refreshSaveStates() }
    }

    private func run(_ action: SlotAction) {
        completed = nil
        Task {
            if action.loading { await session.restoreSaveState(slot: action.slot) }
            else { await session.writeSaveState(slot: action.slot) }
            if session.saveStateMessage == nil, session.canPause {
                completed = action.loading ? "State loaded. Close this menu and resume when ready." : "State saved to slot \(action.slot)."
            }
        }
    }
}
