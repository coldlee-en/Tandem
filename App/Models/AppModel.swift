import Combine
import Foundation
import EmulationKit

private actor LibraryStore {
    private let library: GameLibrary
    init(rootURL: URL) throws { library = try GameLibrary(rootURL: rootURL) }
    func games() -> [GameRecord] { library.games }
    func fileURL(for game: GameRecord) throws -> URL { try library.fileURL(for: game) }
    func importGame(_ url: URL) throws -> [GameRecord] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try library.importGame(from: url)
        return library.games
    }
    func remove(_ game: GameRecord) throws -> [GameRecord] {
        try library.remove(game)
        return library.games
    }
    func markPlayed(_ game: GameRecord) throws -> [GameRecord] {
        try library.markPlayed(game)
        return library.games
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var games: [GameRecord] = []
    @Published var errorMessage: String?
    @Published private(set) var isImporting = false
    @Published private(set) var isManagingSystemData = false
    @Published var systemDataMessage: String?
    let session: EmulationSession
    let systemDirectory: URL
    private let store: LibraryStore?
    private let systemFiles = SystemFileStore()

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = documents.appendingPathComponent("Tandem", isDirectory: true)
        systemDirectory = root.appendingPathComponent("System", isDirectory: true)
        session = EmulationSession(systemDirectory: systemDirectory)
        do {
            for component in ["3DS", "Switch/system"] {
                try FileManager.default.createDirectory(
                    at: systemDirectory.appendingPathComponent(component), withIntermediateDirectories: true)
            }
            store = try LibraryStore(rootURL: root)
        } catch {
            store = nil
            errorMessage = "The library could not be opened: \(error.localizedDescription)"
        }
        session.didStart = { [weak self] game in
            Task { await self?.recordPlayed(game) }
        }
        Task { if let store { games = await store.games() } }
    }

    func importGames(_ urls: [URL]) {
        guard !isImporting, let store else { return }
        isImporting = true
        Task {
            defer { isImporting = false }
            var failures: [String] = []
            for url in urls {
                do { games = try await store.importGame(url) }
                catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
        }
    }

    func remove(_ game: GameRecord) {
        guard session.game?.id != game.id, let store else { return }
        Task {
            do { games = try await store.remove(game) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func launch(_ game: GameRecord) {
        guard session.game == nil, !isManagingSystemData, let store else { return }
        Task {
            do {
                let fileURL = try await store.fileURL(for: game)
                guard !isManagingSystemData else { return }
                try session.prepare(game, fileURL: fileURL)
            }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func importThreeDSData(_ url: URL, seedDatabase: Bool) {
        guard session.game == nil, !isManagingSystemData else { return }
        isManagingSystemData = true
        systemDataMessage = nil
        Task {
            defer { isManagingSystemData = false }
            do {
                try await systemFiles.importThreeDSData(from: url, systemDirectory: systemDirectory, seedDatabase: seedDatabase)
                systemDataMessage = seedDatabase ? "3DS seed database imported." : "3DS AES keys imported. The core will verify them when loading your game."
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func importSwitchKeys(_ url: URL) {
        guard session.game == nil, !isManagingSystemData else { return }
        isManagingSystemData = true
        systemDataMessage = nil
        Task {
            defer { isManagingSystemData = false }
            do {
                try await systemFiles.importSwitchKeys(from: url, systemDirectory: systemDirectory)
                systemDataMessage = "Switch keys imported. The core will validate them when loading content."
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func installSwitchFirmware(_ url: URL) {
        guard session.game == nil, !isManagingSystemData else { return }
        isManagingSystemData = true
        systemDataMessage = nil
        Task {
            defer { isManagingSystemData = false }
            do {
                let version = try await SwitchCore.installFirmware(from: url, systemDirectory: systemDirectory)
                systemDataMessage = "Switch firmware \(version) installed."
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func recordPlayed(_ game: GameRecord) async {
        guard let store else { return }
        do { games = try await store.markPlayed(game) }
        catch { errorMessage = "Could not update the play date: \(error.localizedDescription)" }
    }
}
