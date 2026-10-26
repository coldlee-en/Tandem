import Foundation

public enum GameLibraryError: Error, LocalizedError {
    case unsupportedFile(String)
    case notARegularFile
    case emptyFile
    case invalidPath
    case missingFile
    case missingRecord
    case invalidIndex

    public var errorDescription: String? {
        switch self {
        case .unsupportedFile(let ext):
            return "The .\(ext) format cannot be imported. Choose a 3DS, CCI, CXI, 3DSX, NRO, NSO, XCI, or NSP file."
        case .notARegularFile: return "Choose a game file instead of a folder."
        case .emptyFile: return "The selected game file is empty."
        case .invalidPath: return "The game library contains an invalid file path."
        case .missingFile: return "The game file is missing. Import it again."
        case .missingRecord: return "This game is no longer in the library."
        case .invalidIndex: return "The saved game library contains invalid or duplicate entries."
        }
    }
}

/// A local, synchronous library. Call its operations from one serial executor.
/// Game files live in app-owned storage, so security-scoped source URLs are only
/// needed for the duration of `importGame(from:)`.
public final class GameLibrary {
    public private(set) var games: [GameRecord]
    public let rootURL: URL

    private let manager = FileManager.default
    private var indexURL: URL { rootURL.appendingPathComponent("library.json") }
    private var romsURL: URL { rootURL.appendingPathComponent("ROMs", isDirectory: true) }
    private var deletionJournalURL: URL { rootURL.appendingPathComponent(".pending-delete.json") }

    public init(rootURL: URL) throws {
        guard rootURL.isFileURL else { throw GameLibraryError.invalidPath }
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        self.games = []
        try manager.createDirectory(at: romsURL, withIntermediateDirectories: true)
        if manager.fileExists(atPath: indexURL.path) {
            let decoded = try JSONDecoder().decode([GameRecord].self, from: Data(contentsOf: indexURL))
            guard Set(decoded.map(\.id)).count == decoded.count,
                  Set(decoded.map(\.relativePath)).count == decoded.count else {
                throw GameLibraryError.invalidIndex
            }
            for game in decoded {
                _ = try validatedURL(for: game)
                guard game.byteCount > 0,
                      game.system.supportedExtensions.contains(URL(fileURLWithPath: game.relativePath).pathExtension) else {
                    throw GameLibraryError.invalidIndex
                }
            }
            games = decoded
        }
        try recoverPendingDeletion()
    }

    @discardableResult
    public func importGame(from sourceURL: URL) throws -> GameRecord {
        guard sourceURL.isFileURL else { throw GameLibraryError.notARegularFile }
        let ext = sourceURL.pathExtension.lowercased()
        guard let system = GameSystem.system(forFileExtension: ext) else {
            throw GameLibraryError.unsupportedFile(ext)
        }
        let attributes = try manager.attributesOfItem(atPath: sourceURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw GameLibraryError.notARegularFile
        }
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard byteCount > 0 else { throw GameLibraryError.emptyFile }

        let id = UUID()
        let relativePath = "ROMs/\(id.uuidString).\(ext)"
        let title = sourceURL.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let game = GameRecord(
            id: id,
            title: title.isEmpty ? "Untitled game" : title,
            system: system,
            relativePath: relativePath,
            byteCount: byteCount
        )
        let destination = try validatedURL(for: game)
        do {
            try manager.copyItem(at: sourceURL, to: destination)
            // Read the copy's actual size in case the source changed while copying.
            let actualSize = try manager.attributesOfItem(atPath: destination.path)[.size] as? NSNumber
            guard actualSize?.int64Value == byteCount else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let updated = [game] + games
            try persist(updated)
            games = updated
            return game
        } catch {
            try? manager.removeItem(at: destination)
            throw error
        }
    }

    public func remove(_ game: GameRecord) throws {
        // A previous committed deletion may still need its trash removed.
        try recoverPendingDeletion()
        guard let current = games.first(where: { $0.id == game.id }) else {
            throw GameLibraryError.missingRecord
        }
        let source = try validatedURL(for: current)
        let backup = try deletionBackupURL(for: current)
        guard !manager.fileExists(atPath: backup.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let fileExists = manager.fileExists(atPath: source.path)
        // The journal is durable before the original file is moved. Recovery
        // consults the atomic index to distinguish rollback from committed cleanup.
        try JSONEncoder().encode(current).write(to: deletionJournalURL, options: .atomic)
        do {
            if fileExists { try manager.moveItem(at: source, to: backup) }
            let updated = games.filter { $0.id != current.id }
            try persist(updated)
            games = updated
        } catch let deletionError {
            // If restoring the file fails, propagate that failure and preserve
            // the journal for a later attempt instead of hiding data loss.
            try recoverPendingDeletion()
            throw deletionError
        }
        do {
            try recoverPendingDeletion()
        } catch {
            // The index has committed and the row is removed. Keep the journal
            // so initialization or the next deletion can retry trash cleanup.
        }
    }

    public func markPlayed(_ game: GameRecord) throws {
        guard let index = games.firstIndex(where: { $0.id == game.id }) else {
            throw GameLibraryError.missingRecord
        }
        var updated = games
        updated[index].lastPlayedAt = Date()
        try persist(updated)
        games = updated
    }

    public func fileURL(for game: GameRecord) throws -> URL {
        guard let current = games.first(where: { $0.id == game.id }) else {
            throw GameLibraryError.missingRecord
        }
        let url = try validatedURL(for: current)
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        guard values?.isRegularFile == true else { throw GameLibraryError.missingFile }
        return url
    }

    private func validatedURL(for game: GameRecord) throws -> URL {
        let pieces = game.relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 2, pieces[0] == "ROMs",
              !pieces[1].isEmpty, !pieces[1].contains("\\"),
              String(pieces[1]).hasPrefix(game.id.uuidString + ".") else {
            throw GameLibraryError.invalidPath
        }
        let candidate = rootURL.appendingPathComponent(game.relativePath).standardizedFileURL
        if let attributes = try? manager.attributesOfItem(atPath: candidate.path),
           attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            throw GameLibraryError.invalidPath
        }
        let url = candidate.resolvingSymlinksInPath()
        let canonicalROMs = romsURL.standardizedFileURL.resolvingSymlinksInPath()
        guard canonicalROMs.path == rootURL.appendingPathComponent("ROMs").path,
              url.deletingLastPathComponent().path == canonicalROMs.path else {
            throw GameLibraryError.invalidPath
        }
        return url
    }

    private func deletionBackupURL(for game: GameRecord) throws -> URL {
        // Validate the ordinary path too: a journal is untrusted persisted data.
        _ = try validatedURL(for: game)
        let candidate = romsURL.appendingPathComponent(".deleting-\(game.id.uuidString)")
        if let attributes = try? manager.attributesOfItem(atPath: candidate.path),
           attributes[.type] as? FileAttributeType != .typeRegular {
            throw GameLibraryError.invalidPath
        }
        let canonical = candidate.standardizedFileURL.resolvingSymlinksInPath()
        guard canonical.path == candidate.path else { throw GameLibraryError.invalidPath }
        return canonical
    }

    private func recoverPendingDeletion() throws {
        guard manager.fileExists(atPath: deletionJournalURL.path) else { return }
        let attributes = try manager.attributesOfItem(atPath: deletionJournalURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw GameLibraryError.invalidPath
        }
        let pending = try JSONDecoder().decode(GameRecord.self, from: Data(contentsOf: deletionJournalURL))
        let source = try validatedURL(for: pending)
        let backup = try deletionBackupURL(for: pending)
        let backupExists = manager.fileExists(atPath: backup.path)

        if let indexed = games.first(where: { $0.id == pending.id }) {
            guard indexed.relativePath == pending.relativePath else { throw GameLibraryError.invalidIndex }
            if backupExists {
                // Never overwrite a replacement file; leave both copies and the
                // journal intact for inspection if the state is ambiguous.
                guard !manager.fileExists(atPath: source.path) else { throw GameLibraryError.invalidIndex }
                try manager.moveItem(at: backup, to: source)
            }
        } else if backupExists {
            try manager.removeItem(at: backup)
        }
        try manager.removeItem(at: deletionJournalURL)
    }

    private func persist(_ records: [GameRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: indexURL, options: .atomic)
    }
}
