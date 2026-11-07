import Foundation
import XCTest
@testable import EmulationKit

final class CollectionCatalogTests: XCTestCase {
    func testMembershipAndNamesSurviveSerialization() throws {
        var catalog = CollectionCatalog()
        let first = try catalog.create(name: "  Adventure   games  ")
        let second = try catalog.create(name: "Favorites to finish")
        let game = UUID()
        try catalog.setMembership(gameID: game, collectionID: first, included: true)
        try catalog.setMembership(gameID: game, collectionID: first, included: true)
        try catalog.setMembership(gameID: game, collectionID: second, included: true)
        try catalog.rename(first, to: "Adventures")
        let restored = try CollectionCatalog(serialized: catalog.serialized())
        XCTAssertEqual(restored, catalog)
        XCTAssertEqual(restored.collections[0].id, first)
        XCTAssertEqual(restored.collections[0].name, "Adventures")
        XCTAssertEqual(restored.collections[0].gameIDs, [game])
        try catalog.setMembership(gameID: game, collectionID: first, included: false)
        XCTAssertFalse(catalog.contains(gameID: game, collectionID: first))
        XCTAssertTrue(catalog.contains(gameID: game, collectionID: second))
    }

    func testInvalidAndDuplicateNamesLeaveCatalogUnchanged() throws {
        var catalog = CollectionCatalog()
        _ = try catalog.create(name: "Pokémon")
        let other = try catalog.create(name: "Racing")
        let before = catalog
        for name in ["", " \n ", String(repeating: "x", count: 65), "Two\nlines"] {
            XCTAssertThrowsError(try catalog.create(name: name))
        }
        XCTAssertThrowsError(try catalog.create(name: " POKEMON "))
        XCTAssertThrowsError(try catalog.rename(other, to: "pokémon"))
        XCTAssertEqual(catalog, before)
        XCTAssertThrowsError(try catalog.setMembership(gameID: UUID(), collectionID: UUID(), included: true))
    }

    func testRejectsUnreadableOrUnsupportedDocuments() throws {
        for text in ["damaged", "[]", #"{"version":2,"collections":[]}"#] {
            XCTAssertThrowsError(try CollectionCatalog(serialized: text))
        }
        var catalog = CollectionCatalog()
        _ = try catalog.create(name: "One")
        let data = Data(try catalog.serialized().utf8)
        var doc = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try XCTUnwrap(doc["collections"] as? [[String: Any]])
        doc["collections"] = entries + entries
        let duplicated = String(decoding: try JSONSerialization.data(withJSONObject: doc), as: UTF8.self)
        XCTAssertThrowsError(try CollectionCatalog(serialized: duplicated))
        XCTAssertTrue(try CollectionCatalog(serialized: "").collections.isEmpty)
    }

    func testRemovingCollectionKeepsGameFilesAndOtherMemberships() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Example.3ds")
        let content = Data([1, 2, 3, 4])
        try content.write(to: source)
        let library = try GameLibrary(rootURL: root.appendingPathComponent("Library"))
        let game = try library.importGame(from: source)
        var catalog = CollectionCatalog()
        let first = try catalog.create(name: "First")
        let second = try catalog.create(name: "Second")
        try catalog.setMembership(gameID: game.id, collectionID: first, included: true)
        try catalog.setMembership(gameID: game.id, collectionID: second, included: true)
        try catalog.remove(first)
        XCTAssertTrue(catalog.contains(gameID: game.id, collectionID: second))
        XCTAssertEqual(try Data(contentsOf: library.fileURL(for: game)), content)
        XCTAssertEqual(library.games, [game])
    }
}
