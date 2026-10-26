import Foundation

actor SystemFileStore {
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
