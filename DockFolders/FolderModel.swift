import AppKit
import Observation

@MainActor
@Observable
final class FolderModel {
    private(set) var folders: [Folder] = []
    var selection: Folder.ID?
    var errorMessage: String?
    /// The Dock caches icons and names; set when a folder that's in the Dock changed.
    var dockNeedsRefresh = false
    private(set) var dockPaths: Set<String> = []

    @ObservationIgnored private var pendingBuilds: [UUID: Task<Void, Never>] = [:]

    init() {
        do {
            folders = try FolderStore.load()
        } catch {
            // Keep the unreadable file instead of overwriting it on the next save.
            let backup = FolderStore.defaultURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: FolderStore.defaultURL, to: backup)
            errorMessage = "folders.json couldn't be read (\(error.localizedDescription)). It was moved to \(backup.lastPathComponent)."
        }
        selection = folders.first?.id
        dockPaths = DockPrefs.paths()
    }

    func folder(_ id: UUID) -> Folder? { folders.first { $0.id == id } }
    func isInDock(_ folder: Folder) -> Bool { dockPaths.contains(StubGenerator.url(for: folder.name).path) }

    // MARK: - Editing

    func addFolder() {
        var name = "New Folder", n = 1
        while nameTaken(name, except: nil) { n += 1; name = "New Folder \(n)" }
        let folder = Folder(id: UUID(), name: name, appPaths: [])
        folders.append(folder)
        selection = folder.id
        changed(folder.id)
    }

    func rename(_ id: UUID, to raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = index(id), name != folders[i].name else { return }
        guard !name.isEmpty else { errorMessage = "A folder needs a name."; return }
        guard !nameTaken(name, except: id) else { errorMessage = "There's already a folder named “\(name)”."; return }

        let old = StubGenerator.url(for: folders[i].name), new = StubGenerator.url(for: name)
        folders[i].name = name
        if FileManager.default.fileExists(atPath: old.path) { try? FileManager.default.moveItem(at: old, to: new) }
        if dockPaths.contains(old.path) {
            editDock { DockPrefs.replacing(old, with: new, label: name, in: $0) }
            dockNeedsRefresh = true
        }
        changed(id)
    }

    func addApps(_ urls: [URL], to id: UUID) {
        guard let i = index(id) else { return }
        let new = urls.filter { $0.pathExtension == "app" }.map(\.path).filter { !folders[i].appPaths.contains($0) }
        guard !new.isEmpty else { return }
        folders[i].appPaths += new
        changed(id)
    }

    func moveApps(in id: UUID, from: IndexSet, to: Int) {
        guard let i = index(id) else { return }
        folders[i].appPaths.move(fromOffsets: from, toOffset: to)
        changed(id)
    }

    func removeApp(_ path: String, from id: UUID) {
        guard let i = index(id) else { return }
        folders[i].appPaths.removeAll { $0 == path }
        changed(id)
    }

    func delete(_ id: UUID) {
        guard let i = index(id) else { return }
        let stub = StubGenerator.url(for: folders[i].name)
        pendingBuilds.removeValue(forKey: id)?.cancel()
        folders.remove(at: i)
        if selection == id { selection = folders.first?.id }
        save()
        try? FileManager.default.trashItem(at: stub, resultingItemURL: nil)
        if dockPaths.contains(stub.path) {
            editDock { DockPrefs.removing(stub, from: $0) }
            refreshDock()
        }
    }

    // MARK: - Dock

    func addToDock(_ id: UUID) {
        guard let folder = folder(id) else { return }
        pendingBuilds.removeValue(forKey: id)?.cancel()
        Task {
            guard await build(folder) else { return }
            let stub = StubGenerator.url(for: folder.name)
            editDock { DockPrefs.adding(stub, label: folder.name, to: $0) }
            refreshDock()
        }
    }

    func refreshDock() {
        DockPrefs.restartDock()
        dockNeedsRefresh = false
    }

    func showInFinder(_ id: UUID) {
        guard let folder = folder(id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([StubGenerator.url(for: folder.name)])
    }

    // MARK: - Private

    private func index(_ id: UUID) -> Int? { folders.firstIndex { $0.id == id } }

    private func nameTaken(_ name: String, except id: UUID?) -> Bool {
        let file = StubGenerator.fileName(for: name).lowercased()
        return folders.contains { $0.id != id && StubGenerator.fileName(for: $0.name).lowercased() == file }
    }

    private func editDock(_ change: ([DockPrefs.Tile]) -> [DockPrefs.Tile]) {
        do { try DockPrefs.update(change) } catch { errorMessage = error.localizedDescription }
        dockPaths = DockPrefs.paths()
    }

    /// Saves now; rebuilds the folder's app once edits pause (icon render + codesign takes a moment).
    private func changed(_ id: UUID) {
        save()
        pendingBuilds[id]?.cancel()
        pendingBuilds[id] = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let folder = folder(id) else { return }
            await build(folder)
        }
    }

    // ponytail: a build already running when a rename lands can leave a stale copy under the old name;
    // serialize builds per folder if that shows up.
    @discardableResult
    private func build(_ folder: Folder) async -> Bool {
        do {
            try await Task.detached { try StubGenerator.generate(folder) }.value
            if isInDock(folder) { dockNeedsRefresh = true }
            return true
        } catch {
            errorMessage = "Couldn't build “\(folder.name)”: \(error.localizedDescription)"
            return false
        }
    }

    private func save() {
        do { try FolderStore.save(folders) } catch { errorMessage = "Couldn't save folders: \(error.localizedDescription)" }
    }
}
