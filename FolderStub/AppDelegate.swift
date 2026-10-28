import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Step 1: hardcoded. Step 2 reads DockFolderID from Info.plist and the list from folders.json.
    static let apps = [
        "/Applications/Safari.app",
        "/System/Applications/Calculator.app",
        "/System/Applications/Calendar.app",
        "/System/Applications/Notes.app",
        "/System/Applications/Reminders.app",
        "/System/Applications/Utilities/Terminal.app",
        "/System/Applications/Utilities/Activity Monitor.app",
        "/Applications/Missing Example.app",
    ].map { URL(fileURLWithPath: $0) }

    private var panel: FolderPanel?
    private var clickMonitor: Any?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = FolderPanel(apps: Self.apps) { [weak self] url in self?.launch(url) }
        panel.place(near: NSEvent.mouseLocation)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        // Backstop if activation was refused: any click in another app dismisses.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
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
