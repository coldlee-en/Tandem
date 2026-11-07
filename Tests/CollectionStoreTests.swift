import Foundation
import XCTest
import EmulationKit
@testable import Tandem

final class CollectionStoreTests: XCTestCase {
    @MainActor
    func testMutationsPersistAndFailedRenameKeepsPreviousData() throws {
        let suite = "Tandem-collections-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryCollectionsStore(defaults: defaults)
        let game = UUID()
        let id = try store.create(name: "Adventure", including: game)
        _ = try store.create(name: "Racing")
        let previous = defaults.string(forKey: CollectionCatalog.storageKey)
        XCTAssertThrowsError(try store.rename(id, to: "racing"))
        XCTAssertEqual(defaults.string(forKey: CollectionCatalog.storageKey), previous)
        let reopened = LibraryCollectionsStore(defaults: defaults)
        XCTAssertEqual(reopened.catalog, store.catalog)
        XCTAssertTrue(reopened.catalog.contains(gameID: game, collectionID: id))
        try reopened.remove(id)
        XCTAssertEqual(LibraryCollectionsStore(defaults: defaults).catalog.collections.count, 1)
    }

    @MainActor
    func testCorruptMetadataIsPreservedUntilExplicitReset() throws {
        let suite = "Tandem-collections-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unreadable metadata", forKey: CollectionCatalog.storageKey)
        defaults.set("favorite game IDs", forKey: "favoriteGames")
        let store = LibraryCollectionsStore(defaults: defaults)
        XCTAssertFalse(store.canEdit)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.create(name: "Do not overwrite"))
        XCTAssertEqual(defaults.string(forKey: CollectionCatalog.storageKey), "unreadable metadata")
        store.reset()
        XCTAssertTrue(store.canEdit)
        XCTAssertNil(store.loadError)
        XCTAssertEqual(defaults.string(forKey: "favoriteGames"), "favorite game IDs")
        XCTAssertNil(defaults.object(forKey: CollectionCatalog.storageKey))
        _ = try store.create(name: "Recovered")
        XCTAssertEqual(store.catalog.collections.first?.name, "Recovered")
    }
}
