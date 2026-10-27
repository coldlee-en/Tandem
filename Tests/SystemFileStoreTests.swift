import Foundation
import XCTest
import UIKit
import ImageIO
@testable import Tandem

final class SystemFileStoreTests: XCTestCase {
    @MainActor
    func testCoverImportCreatesBoundedImageAndRejectsInvalidData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("cover.png")
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 600)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 600))
        }
        try XCTUnwrap(rendered.pngData()).write(to: source)
        let gameID = UUID()
        let system = root.appendingPathComponent("System", isDirectory: true)
        let store = SystemFileStore()
        try await store.importCover(from: source, gameID: gameID, systemDirectory: system)
        let target = root.appendingPathComponent("Artwork/\(gameID.uuidString).jpg")
        let original = try Data(contentsOf: target)
        let image = try XCTUnwrap(CGImageSourceCreateWithData(original as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any])
        XCTAssertLessThanOrEqual(try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int), 1024)
        try Data("not an image".utf8).write(to: source)
        do {
            try await store.importCover(from: source, gameID: gameID, systemDirectory: system)
            XCTFail("Invalid image was accepted")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

    func testNewAESImportsUseCoreSystemDataDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("sample.txt")
        try Data("generatorConstant=00000000000000000000000000000000\nslot0x2CKeyX=11111111111111111111111111111111\n".utf8).write(to: source)
        try await SystemFileStore().importThreeDSData(from: source, systemDirectory: root, seedDatabase: false)
        let destination = root.appendingPathComponent("3DS/system_data/keys.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(try String(contentsOf: destination, encoding: .utf8).hasPrefix(":AES\n"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("3DS/sysdata/keys.txt").path))
    }

    func testMigratesOldKeysAndSeedsWithoutOverwritingNewFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("3DS/sysdata", isDirectory: true)
        let current = root.appendingPathComponent("3DS/system_data", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try Data("old-key".utf8).write(to: old.appendingPathComponent("keys.txt"))
        try Data("old-seed".utf8).write(to: old.appendingPathComponent("seeddb.bin"))
        try Data("new-key".utf8).write(to: current.appendingPathComponent("keys.txt"))
        let store = SystemFileStore()
        try await store.migrateThreeDSData(systemDirectory: root)
        try await store.migrateThreeDSData(systemDirectory: root)
        XCTAssertEqual(try Data(contentsOf: current.appendingPathComponent("keys.txt")), Data("new-key".utf8))
        XCTAssertEqual(try Data(contentsOf: current.appendingPathComponent("seeddb.bin")), Data("old-seed".utf8))
        XCTAssertEqual(try Data(contentsOf: old.appendingPathComponent("keys.txt")), Data("old-key".utf8))
    }
}
