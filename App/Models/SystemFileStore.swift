import Foundation
import EmulationKit
import ImageIO
import UniformTypeIdentifiers

actor SystemFileStore {
    func importCover(from url: URL, gameID: UUID, systemDirectory: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size < 20 * 1_048_576,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary) else {
            throw EmulationError.startFailed("Choose a valid image smaller than 20 MB.")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw EmulationError.startFailed("Could not create the cover image.")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw EmulationError.startFailed("Could not save the cover image.")
        }
        let folder = systemDirectory.deletingLastPathComponent().appendingPathComponent("Artwork", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try (data as Data).write(to: folder.appendingPathComponent(gameID.uuidString + ".jpg"), options: .atomic)
    }

    /// Recover imports made by 0.1.1 without replacing data already in use.
    func migrateThreeDSData(systemDirectory: URL) throws {
        let old = systemDirectory.appendingPathComponent("3DS/sysdata", isDirectory: true)
        let current = systemDirectory.appendingPathComponent("3DS/system_data", isDirectory: true)
        for name in ["keys.txt", "seeddb.bin"] {
            let source = old.appendingPathComponent(name)
            let destination = current.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path),
                  !FileManager.default.fileExists(atPath: destination.path) else { continue }
            try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    func importThreeDSData(from url: URL, systemDirectory: URL, seedDatabase: Bool) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let limit = seedDatabase ? 32 * 1_048_576 : 1_048_576
        let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard attributes.isRegularFile == true, let size = attributes.fileSize, size > 0, size < limit else {
            throw EmulationError.startFailed("Choose a valid \(seedDatabase ? "seed database smaller than 32 MB" : "AES keys file smaller than 1 MB").")
        }
        var data = try Data(contentsOf: url)
        if seedDatabase { try ThreeDSKeyFile.validateSeedDatabase(data) }
        else { data = try ThreeDSKeyFile.normalize(data) }
        let directory = systemDirectory.appendingPathComponent("3DS/system_data", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(seedDatabase ? "seeddb.bin" : "keys.txt"),
                       options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    func importSwitchKeys(from url: URL, systemDirectory: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size < 1_048_576 else {
            throw EmulationError.startFailed("Choose a nonempty prod.keys text file smaller than 1 MB.")
        }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8), text.contains("="), !text.contains("\0") else {
            throw EmulationError.startFailed("The selected file is not a keys text file.")
        }
        let directory = systemDirectory.appendingPathComponent("Switch/system", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("prod.keys"), options: .atomic)
    }
}
