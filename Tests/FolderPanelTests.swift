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
}
