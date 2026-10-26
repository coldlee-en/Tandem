import Foundation
import EmulationKit

actor SystemFileStore {
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
        let directory = systemDirectory.appendingPathComponent("3DS/sysdata", isDirectory: true)
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
