import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var folderID: UUID? { Bundle.main.dockFolderID }

    /// This folder: DockFolderID from our Info.plist, contents from folders.json.
    static func loadFolder() -> Folder? {
        guard let id = folderID else { return nil }
        return (try? FolderStore.load())?.first { $0.id == id }
    }

    private var panel: FolderPanel?
    private var clickMonitor: Any?
    private var activationObserver: Any?
    /// Files dropped on the folder's Dock tile; picking an app opens them in it.
    private var droppedFiles: [URL] = []
    private var notice: String?
    /// Apps just dropped on us; shown right away, before the manager has saved them.
    private var pendingAdds: [String] = []
    private var didLaunch = false

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Only apps dropped: add them to the folder. Anything else (or a mix): pick an app to open it with.
        let apps = urls.filter { $0.pathExtension == "app" }
        if apps.count == urls.count, let added = addToFolder(apps) {
            droppedFiles = []
            notice = switch added.count {
            case 0: "Already in this folder"
            case 1: "Added “\(FileManager.default.displayName(atPath: added[0]))”"
            default: "Added \(added.count) apps"
            }
        } else {
            droppedFiles = urls
            notice = nil
        }
        if didLaunch { showPanel() } // dropped while the folder was already open: show it again
    }

    /// Asks the manager (the only writer of folders.json) to add the apps; returns the ones that are new.
    /// nil if this folder can't be found, so the drop falls back to "Open … with".
    private func addToFolder(_ apps: [URL]) -> [String]? {
        guard let id = Self.folderID, var folder = Self.loadFolder() else {
            requestLog.error("drop: folder not found in folders.json; offering Open With instead")
            return nil
        }
        let added = folder.addApps(apps)
        if !added.isEmpty {
            ManagerRequest.add.send(folderID: id, paths: added, folderAppBundleID: Bundle.main.bundleIdentifier ?? "")
        }
        pendingAdds = added
        return added
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didLaunch = true
        showPanel()
        // We never become the active app (macOS refuses focus to Dock-launched UI-element apps), so dismiss
        // on any click in another app, or when another app comes to the front (e.g. Cmd-Tab).
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            // Ignore our own activation (opening files can activate us); any other app means the user moved on.
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
    }

    private func showPanel() {
        panel?.orderOut(nil)
        let folder = Self.loadFolder()
        var paths = folder?.appPaths ?? []
        for path in pendingAdds where !paths.contains(path) { paths.append(path) }
        let apps = paths.map { URL(fileURLWithPath: $0) }
        let panel = FolderPanel(apps: apps, layout: folder?.layout ?? .grid, files: droppedFiles,
                                notice: notice) { [weak self] url in
            self?.launch(url)
        }
        panel.show(near: NSEvent.mouseLocation)
        self.panel = panel
    }

    // Dock click while the grid is open toggles it closed, like a stack.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    func applicationDidResignActive(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    private func launch(_ url: URL) {
        panel?.orderOut(nil)
        let files = droppedFiles
        Task {
            let config = NSWorkspace.OpenConfiguration()
            if files.isEmpty {
                _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
            } else {
                _ = try? await NSWorkspace.shared.open(files, withApplicationAt: url, configuration: config)
            }
            NSApp.terminate(nil)
        }
    }
}
