import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var folderID: UUID? {
        (Bundle.main.object(forInfoDictionaryKey: StubInfo.folderIDKey) as? String).flatMap(UUID.init(uuidString:))
    }

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

    /// Adds the apps to this folder in folders.json; nil if the folder can't be found or saved.
    private func addToFolder(_ apps: [URL]) -> [String]? {
        guard let id = Self.folderID else { return nil }
        var added: [String] = []
        guard (try? FolderStore.update(id) { added = $0.addApps(apps) }) == true else { return nil }
        if !added.isEmpty { Self.requestRebuild(id) }
        return added
    }

    /// The manager owns icon rendering: ask it to rebuild this folder app (and refresh the Dock).
    private static func requestRebuild(_ id: UUID) {
        guard let managerID = StubInfo.managerBundleID(fromStubID: Bundle.main.bundleIdentifier ?? "") else { return }
        if !NSRunningApplication.runningApplications(withBundleIdentifier: managerID).isEmpty {
            DistributedNotificationCenter.default().postNotificationName(
                .init(StubInfo.folderChangedNotification(managerBundleID: managerID)),
                object: id.uuidString, userInfo: nil, deliverImmediately: true)
        } else if let manager = NSWorkspace.shared.urlForApplication(withBundleIdentifier: managerID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.arguments = [StubInfo.backgroundArgument, StubInfo.rebuildArgument, id.uuidString]
            NSWorkspace.shared.openApplication(at: manager, configuration: config)
        }
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
