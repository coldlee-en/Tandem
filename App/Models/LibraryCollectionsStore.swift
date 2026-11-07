import Combine
import Foundation
import EmulationKit

@MainActor
final class LibraryCollectionsStore: ObservableObject {
    @Published private(set) var catalog = CollectionCatalog()
    @Published private(set) var loadError: String?
    private let defaults: UserDefaults
    var canEdit: Bool { loadError == nil }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let saved = defaults.object(forKey: CollectionCatalog.storageKey) else { return }
        guard let text = saved as? String else {
            loadError = CollectionError.invalidData.localizedDescription
            return
        }
        do { catalog = try CollectionCatalog(serialized: text) }
        catch { loadError = error.localizedDescription }
    }

    @discardableResult
    func create(name: String, including gameID: UUID? = nil) throws -> UUID {
        try edit { catalog in
            let id = try catalog.create(name: name)
            if let gameID { try catalog.setMembership(gameID: gameID, collectionID: id, included: true) }
            return id
        }
    }

    func rename(_ id: UUID, to name: String) throws {
        try edit { try $0.rename(id, to: name) }
    }

    func remove(_ id: UUID) throws {
        try edit { try $0.remove(id) }
    }

    func setMembership(gameID: UUID, collectionID: UUID, included: Bool) throws {
        try edit { try $0.setMembership(gameID: gameID, collectionID: collectionID, included: included) }
    }

    /// Explicit user recovery. Remove only the collection preference, not game data.
    func reset() {
        defaults.removeObject(forKey: CollectionCatalog.storageKey)
        catalog = CollectionCatalog()
        loadError = nil
    }

    private func edit<T>(_ action: (inout CollectionCatalog) throws -> T) throws -> T {
        guard canEdit else { throw CollectionError.invalidData }
        var updated = catalog
        let result = try action(&updated)
        let text = try updated.serialized()
        defaults.set(text, forKey: CollectionCatalog.storageKey)
        catalog = updated
        return result
    }
}
