import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// This folder: DockFolderID from our Info.plist, contents from folders.json.
    static func loadFolder() -> Folder? {
        guard let idString = Bundle.main.object(forInfoDictionaryKey: StubInfo.folderIDKey) as? String,
              let id = UUID(uuidString: idString) else { return nil }
        return (try? FolderStore.load())?.first { $0.id == id }
    }

    private var panel: FolderPanel?
    private var clickMonitor: Any?
    private var activationObserver: Any?
    /// Files dropped on the folder's Dock tile; picking an app opens them in it.
    private var droppedFiles: [URL] = []
    private var didLaunch = false

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        droppedFiles = urls
        if didLaunch { showPanel() } // dropped while the folder was already open: show it for these files
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
        let apps = (folder?.appPaths ?? []).map { URL(fileURLWithPath: $0) }
        let panel = FolderPanel(apps: apps, layout: folder?.layout ?? .grid, files: droppedFiles) { [weak self] url in
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
