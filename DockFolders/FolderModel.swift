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

    static let rebuildDelay: Duration = .milliseconds(400)
    /// Latest build per folder. Each build waits for the previous one, so two never write the same app at once.
    @ObservationIgnored private var builds: [UUID: Task<Bool, Never>] = [:]
    @ObservationIgnored private var requestObservers: [Any] = []
    /// Bumped to ask the UI to open the window (the model can't call SwiftUI's openWindow itself).
    var windowRequests = 0

    init() {
        do {
            folders = try FolderStore.load()
        } catch {
            // Keep the unreadable file instead of overwriting it on the next save.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = FolderStore.defaultURL.appendingPathExtension("corrupt-\(stamp)")
            try? FileManager.default.moveItem(at: FolderStore.defaultURL, to: backup)
            errorMessage = "folders.json couldn't be read (\(error.localizedDescription)). It was moved to \(backup.lastPathComponent)."
        }
        selection = folders.first?.id
        dockPaths = DockPrefs.paths()

        // Folder apps and their Dock menus send requests (see ManagerRequest): by notification while we
        // run, or as launch arguments.
        let managerID = Bundle.main.bundleIdentifier ?? ""
        for request in ManagerRequest.allCases {
            requestObservers.append(DistributedNotificationCenter.default().addObserver(
                forName: request.notificationName(managerBundleID: managerID), object: nil, queue: .main
            ) { [weak self] note in
                let id = (note.object as? String).flatMap(UUID.init(uuidString:))
                MainActor.assumeIsolated { if let id { self?.handle(request, for: id) } }
            })
            if let id = request.folderID(in: CommandLine.arguments) { handle(request, for: id) }
        }
    }

    private func handle(_ request: ManagerRequest, for id: UUID) {
        switch request {
        case .rebuild: folderChangedOnDisk(id)
        case .edit:
            if folder(id) == nil, let fresh = try? FolderStore.load() { folders = fresh }
            selection = id
            windowRequests += 1
        }
    }

    /// A folder app added apps to folders.json: reload, rebuild its icon, and restart the Dock so it shows.
    func folderChangedOnDisk(_ id: UUID) {
        if let fresh = try? FolderStore.load() { folders = fresh }
        let build = scheduleBuild(id, after: .zero)
        Task {
            guard await build.value, let folder = folder(id) else { return }
            reloadDockState()
            if isInDock(folder) { refreshDock() }
        }
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
        reloadDockState()
        if dockPaths.contains(old.path), editDockEverywhere({ DockPrefs.replacing(old, with: new, label: name, in: $0) }) {
            // The running Dock still holds the old path and would write it back, so restart it once the
            // renamed app is rebuilt (new name and icon in one restart).
            save()
            let build = scheduleBuild(id, after: .zero)
            Task {
                _ = await build.value
                refreshDock()
            }
            return
        }
        changed(id)
    }

    func addApps(_ urls: [URL], to id: UUID) {
        guard let i = index(id), !folders[i].addApps(urls).isEmpty else { return }
        changed(id)
    }

    func moveApps(in id: UUID, from: IndexSet, to: Int) {
        guard let i = index(id) else { return }
        folders[i].appPaths.move(fromOffsets: from, toOffset: to)
        changed(id)
    }

    func setLayout(_ layout: FolderLayout, for id: UUID) {
        guard let i = index(id), folders[i].layout != layout else { return }
        folders[i].layout = layout
        changed(id) // rebuild: folder apps made by an older DockFolders don't know about layouts
    }

    func setColor(_ color: FolderColor, for id: UUID) {
        guard let i = index(id), folders[i].color != color else { return }
        folders[i].color = color
        changed(id) // icon rebuild
    }

    func removeApp(_ path: String, from id: UUID) {
        guard let i = index(id) else { return }
        folders[i].appPaths.removeAll { $0 == path }
        changed(id)
    }

    func delete(_ id: UUID) {
        guard let i = index(id) else { return }
        let stub = StubGenerator.url(for: folders[i].name)
        builds[id]?.cancel() // a build already running is cleaned up by build() once it sees the folder is gone
        folders.remove(at: i)
        if selection == id { selection = folders.first?.id }
        save()
        try? FileManager.default.trashItem(at: stub, resultingItemURL: nil)
        reloadDockState()
        if dockPaths.contains(stub.path), editDockEverywhere({ DockPrefs.removing(stub, from: $0) }) {
            refreshDock()
        }
    }

    // MARK: - Dock

    func addToDock(_ id: UUID) {
        let build = scheduleBuild(id, after: .zero)
        Task {
            // Look the folder up again: it may have been renamed or deleted while building.
            guard await build.value, let folder = folder(id) else { return }
            let stub = StubGenerator.url(for: folder.name)
            reloadDockState() // already on either side (e.g. dragged in while we were open): don't add a second tile
            guard !isInDock(folder) else { return }
            if editDock(.others, { DockPrefs.adding(stub, label: folder.name, to: $0) }) { refreshDock() }
        }
    }

    /// Re-reads the Dock, which the user can change by hand (e.g. dragging a folder app in).
    func reloadDockState() {
        dockPaths = DockPrefs.paths()
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

    /// Returns false if the edit failed (error shown) or changed nothing.
    @discardableResult
    private func editDock(_ list: DockPrefs.List, _ change: ([DockPrefs.Tile]) -> [DockPrefs.Tile]) -> Bool {
        defer { reloadDockState() }
        do { return try DockPrefs.update(list, change) } catch { errorMessage = error.localizedDescription; return false }
    }

    /// Applies `change` to both sides of the Dock: a folder may sit on either (left from older versions
    /// or moved there by hand). Returns whether either side changed.
    private func editDockEverywhere(_ change: ([DockPrefs.Tile]) -> [DockPrefs.Tile]) -> Bool {
        DockPrefs.List.allCases.map { editDock($0, change) }.contains(true)
    }

    /// Saves now; rebuilds the folder's app once edits pause (icon render + codesign takes a moment).
    private func changed(_ id: UUID) {
        save()
        scheduleBuild(id, after: Self.rebuildDelay)
    }

    @discardableResult
    private func scheduleBuild(_ id: UUID, after delay: Duration) -> Task<Bool, Never> {
        let previous = builds[id]
        previous?.cancel() // stops it if it's still waiting out its delay
        let task = Task {
            _ = await previous?.value
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let folder = folder(id) else { return false }
            return await build(folder)
        }
        builds[id] = task
        return task
    }

    private func build(_ folder: Folder) async -> Bool {
        let built = StubGenerator.url(for: folder.name)
        do {
            try await Task.detached { try StubGenerator.generate(folder) }.value
        } catch {
            errorMessage = "Couldn't build “\(folder.name)”: \(error.localizedDescription)"
            return false
        }
        // Deleted or renamed while building: don't leave an orphan app behind.
        guard self.folder(folder.id)?.name == folder.name else {
            if !folders.contains(where: { StubGenerator.url(for: $0.name) == built }) {
                try? FileManager.default.removeItem(at: built)
            }
            return false
        }
        if isInDock(folder) { dockNeedsRefresh = true }
        return true
    }

    private func save() {
        do { try FolderStore.save(folders) } catch { errorMessage = "Couldn't save folders: \(error.localizedDescription)" }
    }
}
