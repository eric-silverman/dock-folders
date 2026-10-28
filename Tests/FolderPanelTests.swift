import AppKit
import Testing

@MainActor
struct FolderPanelTests {
    // Regression: a Dock-launched LSUIElement app is refused activation, and a regular NSPanel hides
    // while its app is inactive, so the grid never appeared.
    @Test func showsWithoutActivatingTheApp() {
        let panel = FolderPanel(apps: []) { _ in }
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.hidesOnDeactivate == false)
        #expect(panel.canBecomeKey) // Escape still reaches it
    }

    @Test func runningAppsMatchThroughSymlinks() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "DockFoldersTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appending(path: "Real/Tool.app"), link = dir.appending(path: "Tool.app")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        // A folder lists the symlink; the running app reports its real (resolved) bundle URL.
        let running = FolderPanel.runningAppPaths([real, nil])
        #expect(running.contains(FolderPanel.canonicalPath(link)))
        #expect(!running.contains(FolderPanel.canonicalPath(dir.appending(path: "Other.app"))))
    }

    @Test func emptyListFolderFallsBackToGridEmptyState() {
        let p = FolderPanel(apps: [], layout: .list) { _ in }
        #expect(p.frame.size == NSSize(width: FolderPanel.cell.width + 2 * FolderPanel.padding,
                                       height: FolderPanel.cell.height + 2 * FolderPanel.padding))
    }

    @Test func listLayoutIsOneColumnAndCapsHeight() {
        let apps = (0..<3).map { URL(fileURLWithPath: "/Applications/App\($0).app") }
        let list = FolderPanel(apps: apps, layout: .list) { _ in }
        #expect(list.frame.width == FolderPanel.row.width + 2 * FolderPanel.listPadding)
        #expect(list.frame.height == 3 * FolderPanel.row.height + 2 * FolderPanel.listPadding)

        let many = (0..<40).map { URL(fileURLWithPath: "/Applications/App\($0).app") }
        let long = FolderPanel(apps: many, layout: .list) { _ in }
        #expect(long.frame.height == FolderPanel.maxListHeight + 2 * FolderPanel.listPadding)
    }
}
