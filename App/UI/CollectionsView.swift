import SwiftUI
import EmulationKit

@MainActor
struct CollectionsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: LibraryCollectionsStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var confirmation: CollectionConfirmation?

    private enum CollectionConfirmation {
        case reset, delete(GameCollection)
        var title: String {
            switch self { case .reset: return "Reset collection information?"; case .delete: return "Delete this collection?" }
        }
        var message: String {
            switch self {
            case .reset: return "This clears collection names and memberships. Games, covers, favorites, and saves stay on this device."
            case .delete: return "Only the collection is removed. Its games and saves stay in your library."
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let message = store.loadError {
                    Section {
                        Text(message)
                        Text("The unreadable information is preserved until you choose to reset it.")
                            .font(.footnote).foregroundStyle(TandemTheme.muted)
                        Button("Reset collections", role: .destructive) { confirmation = .reset }
                    }
                }
                Section("New collection") {
                    TextField("Collection name", text: $name).submitLabel(.done).onSubmit(create)
                    Button("Create collection", systemImage: "folder.badge.plus", action: create)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.disabled(!store.canEdit)
                Section {
                    if store.catalog.collections.isEmpty {
                        Text("Create a collection, then choose which games belong in it.")
                            .foregroundStyle(TandemTheme.muted)
                    }
                    ForEach(store.catalog.collections) { collection in
                        NavigationLink {
                            CollectionEditorView(collection: collection, model: model, store: store)
                        } label: {
                            HStack {
                                Label(collection.name, systemImage: "folder")
                                Spacer()
                                Text("\(count(collection))").foregroundStyle(TandemTheme.muted)
                            }
                        }
                        .swipeActions {
                            Button("Delete") { confirmation = .delete(collection) }.tint(.red)
                        }
                    }
                } header: {
                    Text("Your collections")
                } footer: {
                    Text("A game can belong to more than one collection. Collections organize your library without copying game files.")
                }
            }
            .scrollContentBackground(.hidden).background(TandemTheme.background)
            .navigationTitle("Collections").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .confirmationDialog(confirmation?.title ?? "Collections", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
                if let action = confirmation {
                    Button("Confirm", role: .destructive) {
                        switch action {
                        case .reset: store.reset()
                        case .delete(let collection):
                            do { try store.remove(collection.id) } catch { errorMessage = error.localizedDescription }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text(confirmation?.message ?? "") }
            .alert("Collections", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }.tint(TandemTheme.mint)
    }

    private func count(_ collection: GameCollection) -> Int {
        model.games.filter { $0.system == .nintendo3DS && collection.gameIDs.contains($0.id) }.count
    }

    private func create() {
        do { try store.create(name: name); name = "" }
        catch { errorMessage = error.localizedDescription }
    }
}

@MainActor
private struct CollectionEditorView: View {
    let collectionID: UUID
    @ObservedObject var model: AppModel
    @ObservedObject var store: LibraryCollectionsStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var search = ""
    @State private var deleting = false
    @State private var errorMessage: String?

    init(collection: GameCollection, model: AppModel, store: LibraryCollectionsStore) {
        collectionID = collection.id
        self.model = model
        self.store = store
        _name = State(initialValue: collection.name)
    }

    private var collection: GameCollection? { store.catalog.collections.first { $0.id == collectionID } }
    private var games: [GameRecord] {
        model.games.filter { $0.system == .nintendo3DS && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        List {
            if let collection {
                Section("Name") {
                    TextField("Collection name", text: $name)
                    Button("Save name") {
                        do { try store.rename(collectionID, to: name) } catch { errorMessage = error.localizedDescription }
                    }
                }
                Section {
                    ForEach(games) { game in
                        Toggle(game.title, isOn: Binding {
                            store.catalog.contains(gameID: game.id, collectionID: collectionID)
                        } set: { included in
                            do { try store.setMembership(gameID: game.id, collectionID: collectionID, included: included) }
                            catch { errorMessage = error.localizedDescription }
                        })
                    }
                    if games.isEmpty { Text("No matching games. Import games from the library to add them here.").foregroundStyle(TandemTheme.muted) }
                } header: { Text("Games") }
                footer: { Text("Turning a game off here removes it from this collection only.") }
                Section {
                    Button("Delete collection", role: .destructive) { deleting = true }
                }
                .confirmationDialog("Delete \(collection.name)?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete collection", role: .destructive) {
                        do { try store.remove(collectionID); dismiss() } catch { errorMessage = error.localizedDescription }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("Games and saves stay in your library.") }
            } else {
                Text("This collection was removed.")
            }
        }
        .scrollContentBackground(.hidden).background(TandemTheme.background)
        .navigationTitle(collection?.name ?? "Collection").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Find games")
        .alert("Collections", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}

@MainActor
struct GameCollectionsView: View {
    let game: GameRecord
    @ObservedObject var store: LibraryCollectionsStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let message = store.loadError { Text(message) }
                    ForEach(store.catalog.collections) { collection in
                        Toggle(collection.name, isOn: Binding {
                            store.catalog.contains(gameID: game.id, collectionID: collection.id)
                        } set: { included in
                            do { try store.setMembership(gameID: game.id, collectionID: collection.id, included: included) }
                            catch { errorMessage = error.localizedDescription }
                        })
                    }
                    if store.catalog.collections.isEmpty {
                        Text("No collections yet. Create one below to add this game.")
                            .foregroundStyle(TandemTheme.muted)
                    }
                } header: { Text(game.title) }
                Section("Create and add") {
                    TextField("Collection name", text: $name)
                    Button("Create collection and add game") {
                        do { try store.create(name: name, including: game.id); name = "" }
                        catch { errorMessage = error.localizedDescription }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.disabled(!store.canEdit)
            }
            .scrollContentBackground(.hidden).background(TandemTheme.background)
            .navigationTitle("Game collections").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .alert("Collections", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }.tint(TandemTheme.mint)
    }
}
