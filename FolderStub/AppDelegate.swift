import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// This folder's apps: DockFolderID from our Info.plist, contents from folders.json.
    static func loadApps() -> [URL] {
        guard let idString = Bundle.main.object(forInfoDictionaryKey: StubInfo.folderIDKey) as? String,
              let id = UUID(uuidString: idString),
              let folder = (try? FolderStore.load())?.first(where: { $0.id == id }) else { return [] }
        return folder.appPaths.map { URL(fileURLWithPath: $0) }
    }

    private var panel: FolderPanel?
    private var clickMonitor: Any?
    private var activationObserver: Any?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = FolderPanel(apps: Self.loadApps()) { [weak self] url in self?.launch(url) }
        panel.show(near: NSEvent.mouseLocation)
        self.panel = panel
        // We never become the active app (macOS refuses focus to Dock-launched UI-element apps), so dismiss
        // on any click in another app, or when another app comes to the front (e.g. Cmd-Tab).
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
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
        Task {
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            NSApp.terminate(nil)
        }
    }
}
