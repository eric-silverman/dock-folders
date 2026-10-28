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
