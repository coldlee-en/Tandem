import Foundation
import XCTest
@testable import EmulationKit

final class GameLibraryTests: XCTestCase {
    private var temporaryURL: URL!

    override func setUpWithError() throws {
        temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryURL)
    }

    private var libraryURL: URL { temporaryURL.appendingPathComponent("Library") }

    private func source(_ name: String, data: Data = Data([0, 1, 2, 3])) throws -> URL {
        let url = temporaryURL.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func testImportCopiesAndPersistsAcrossLaunches() throws {
        let input = try source("Example.3DS")
        let library = try GameLibrary(rootURL: libraryURL)
        let game = try library.importGame(from: input)
        XCTAssertEqual(game.title, "Example")
        XCTAssertEqual(game.system, .nintendo3DS)
        XCTAssertEqual(game.byteCount, 4)
        XCTAssertEqual(try Data(contentsOf: library.fileURL(for: game)), Data([0, 1, 2, 3]))
        try FileManager.default.removeItem(at: input)
        let reopened = try GameLibrary(rootURL: libraryURL)
        XCTAssertEqual(reopened.games, [game])
        XCTAssertTrue(FileManager.default.fileExists(atPath: try reopened.fileURL(for: game).path))
    }

    func testImportsSwitchHomebrewAndRejectsCIAAndArchives() throws {
        let library = try GameLibrary(rootURL: libraryURL)
        XCTAssertEqual(try library.importGame(from: source("Homebrew.nro")).system, .nintendoSwitch)
        for name in ["Game.cia", "Game.zip", "Game.txt"] {
            XCTAssertThrowsError(try library.importGame(from: source(name))) { error in
                guard case GameLibraryError.unsupportedFile = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
        XCTAssertEqual(library.games.count, 1)
    }

    func testRejectsEmptyFilesAndFolders() throws {
        let library = try GameLibrary(rootURL: libraryURL)
        XCTAssertThrowsError(try library.importGame(from: source("Empty.3ds", data: Data())))
        let folder = temporaryURL.appendingPathComponent("Folder.nro", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertThrowsError(try library.importGame(from: folder))
        XCTAssertTrue(library.games.isEmpty)
    }

    func testRemovingGameDeletesManagedCopyAndPersists() throws {
        let library = try GameLibrary(rootURL: libraryURL)
        let input = try source("Example.nsp")
        let game = try library.importGame(from: input)
        let managed = try library.fileURL(for: game)
        try library.remove(game)
        XCTAssertFalse(FileManager.default.fileExists(atPath: managed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
        XCTAssertTrue(try GameLibrary(rootURL: libraryURL).games.isEmpty)
        XCTAssertThrowsError(try library.fileURL(for: game))
    }

    func testMarkPlayedPersistsDate() throws {
        let library = try GameLibrary(rootURL: libraryURL)
        let game = try library.importGame(from: source("Example.3dsx"))
        XCTAssertNil(game.lastPlayedAt)
        try library.markPlayed(game)
        let reopened = try GameLibrary(rootURL: libraryURL)
        XCTAssertNotNil(reopened.games.first?.lastPlayedAt)
    }

    func testRejectsPathTraversalInSavedIndex() throws {
        _ = try GameLibrary(rootURL: libraryURL)
        let malicious = GameRecord(
            title: "Escape", system: .nintendo3DS,
            relativePath: "ROMs/../../outside.3ds", byteCount: 4
        )
        try JSONEncoder().encode([malicious]).write(to: libraryURL.appendingPathComponent("library.json"))
        XCTAssertThrowsError(try GameLibrary(rootURL: libraryURL)) { error in
            guard case GameLibraryError.invalidPath = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testRejectsSymlinkEscapeFromManagedStorage() throws {
        let library = try GameLibrary(rootURL: libraryURL)
        let game = try library.importGame(from: source("Example.3ds"))
        let managed = try library.fileURL(for: game)
        let outside = try source("outside.3ds")
        try FileManager.default.removeItem(at: managed)
        try FileManager.default.createSymbolicLink(at: managed, withDestinationURL: outside)
        XCTAssertThrowsError(try library.fileURL(for: game))
        XCTAssertThrowsError(try GameLibrary(rootURL: libraryURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testFailedIndexWriteRollsBackImport() throws {
        let library = try GameLibrary(rootURL: libraryURL)
        // A directory at the index path makes an atomic JSON replacement fail.
        try FileManager.default.createDirectory(at: libraryURL.appendingPathComponent("library.json"), withIntermediateDirectories: false)
        XCTAssertThrowsError(try library.importGame(from: source("Example.3ds")))
        XCTAssertTrue(library.games.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: libraryURL.appendingPathComponent("ROMs").path).isEmpty)
    }

    func testFailedIndexWriteRestoresRemovedFile() throws {
        let library = try GameLibrary(rootURL: libraryURL)
        let game = try library.importGame(from: source("Example.nro"))
        let managed = try library.fileURL(for: game)
        let index = libraryURL.appendingPathComponent("library.json")
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
        XCTAssertThrowsError(try library.remove(game))
        XCTAssertEqual(library.games, [game])
        XCTAssertTrue(FileManager.default.fileExists(atPath: managed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryURL.appendingPathComponent(".pending-delete.json").path))
    }

    private func journalDeletion(_ game: GameRecord, movingFileFrom managed: URL?) throws -> URL {
        let journal = libraryURL.appendingPathComponent(".pending-delete.json")
        try JSONEncoder().encode(game).write(to: journal, options: .atomic)
        let backup = libraryURL.appendingPathComponent("ROMs/.deleting-\(game.id.uuidString)")
        if let managed { try FileManager.default.moveItem(at: managed, to: backup) }
        return backup
    }

    func testInterruptedDeletionRestoresIndexedGameOnReopen() throws {
        let library = try GameLibrary(rootURL: libraryURL)
        let game = try library.importGame(from: source("Example.3ds"))
        let managed = try library.fileURL(for: game)
        let backup = try journalDeletion(game, movingFileFrom: managed)

        let reopened = try GameLibrary(rootURL: libraryURL)
        XCTAssertEqual(reopened.games, [game])
        XCTAssertEqual(try Data(contentsOf: reopened.fileURL(for: game)), Data([0, 1, 2, 3]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryURL.appendingPathComponent(".pending-delete.json").path))
    }

    func testCommittedDeletionCleansBackupOnReopen() throws {
        let library = try GameLibrary(rootURL: libraryURL)
        let game = try library.importGame(from: source("Example.nro"))
        let managed = try library.fileURL(for: game)
        let backup = try journalDeletion(game, movingFileFrom: managed)
        // Simulate a crash after the atomic index commit and before trash cleanup.
        try JSONEncoder().encode([GameRecord]()).write(to: libraryURL.appendingPathComponent("library.json"), options: .atomic)

        let reopened = try GameLibrary(rootURL: libraryURL)
        XCTAssertTrue(reopened.games.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: managed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryURL.appendingPathComponent(".pending-delete.json").path))
    }

    func testInterruptedDeletionBeforeMoveKeepsOriginalFile() throws {
        let library = try GameLibrary(rootURL: libraryURL)
        let game = try library.importGame(from: source("Example.3dsx"))
        let managed = try library.fileURL(for: game)
        _ = try journalDeletion(game, movingFileFrom: nil)

        let reopened = try GameLibrary(rootURL: libraryURL)
        XCTAssertEqual(try reopened.fileURL(for: game), managed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryURL.appendingPathComponent(".pending-delete.json").path))
    }

    func testNextDeletionRecoversExistingPendingJournalFirst() throws {
        let library = try GameLibrary(rootURL: libraryURL)
        let first = try library.importGame(from: source("First.3ds"))
        let second = try library.importGame(from: source("Second.nro"))
        let firstURL = try library.fileURL(for: first)
        _ = try journalDeletion(first, movingFileFrom: firstURL)

        try library.remove(second)
        XCTAssertEqual(library.games, [first])
        XCTAssertEqual(try Data(contentsOf: library.fileURL(for: first)), Data([0, 1, 2, 3]))
    }

    func testRecoveryDoesNotOverwriteReplacementFileOrDiscardBackup() throws {
        let library = try GameLibrary(rootURL: libraryURL)
        let game = try library.importGame(from: source("Example.3ds"))
        let managed = try library.fileURL(for: game)
        let backup = try journalDeletion(game, movingFileFrom: managed)
        try Data([9, 9, 9]).write(to: managed)

        XCTAssertThrowsError(try GameLibrary(rootURL: libraryURL))
        XCTAssertEqual(try Data(contentsOf: backup), Data([0, 1, 2, 3]))
        XCTAssertEqual(try Data(contentsOf: managed), Data([9, 9, 9]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryURL.appendingPathComponent(".pending-delete.json").path))
    }

    func testRecoveryRejectsBackupSymlinkWithoutTouchingTarget() throws {
        let library = try GameLibrary(rootURL: libraryURL)
        let game = try library.importGame(from: source("Example.nro"))
        let outside = try source("outside.nro")
        let backup = try journalDeletion(game, movingFileFrom: nil)
        try FileManager.default.createSymbolicLink(at: backup, withDestinationURL: outside)

        XCTAssertThrowsError(try GameLibrary(rootURL: libraryURL)) { error in
            guard case GameLibraryError.invalidPath = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: outside), Data([0, 1, 2, 3]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryURL.appendingPathComponent(".pending-delete.json").path))
    }

    func testRejectsManagedSymlinkToAnotherGameInSameDirectory() throws {
        let library = try GameLibrary(rootURL: libraryURL)
        let first = try library.importGame(from: source("First.3ds"))
        let second = try library.importGame(from: source("Second.3ds"))
        let firstURL = try library.fileURL(for: first)
        let secondURL = try library.fileURL(for: second)
        try FileManager.default.removeItem(at: firstURL)
        try FileManager.default.createSymbolicLink(at: firstURL, withDestinationURL: secondURL)

        XCTAssertThrowsError(try library.remove(first))
        XCTAssertEqual(try Data(contentsOf: secondURL), Data([0, 1, 2, 3]))
    }
}
