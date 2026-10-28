import AppKit
import Testing
import UniformTypeIdentifiers

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

    @Test func onlyAppsThatOpenEveryDroppedFileCount() {
        let a = URL(fileURLWithPath: "/Applications/A.app"), b = URL(fileURLWithPath: "/Applications/B.app")
        let c = URL(fileURLWithPath: "/Applications/C.app")
        #expect(FolderPanel.appsAbleToOpenAll([]) == [])
        #expect(FolderPanel.appsAbleToOpenAll([[a, b]]) == [a.path, b.path])
        #expect(FolderPanel.appsAbleToOpenAll([[a, b], [b, c]]) == [b.path])
        #expect(FolderPanel.appsAbleToOpenAll([[a], []]) == [])
    }

    @Test func droppedFilesAddAHeaderAndWidenSmallGrids() {
        let apps = [URL(fileURLWithPath: "/Applications/A.app")]
        let files = [URL(fileURLWithPath: "/tmp/Quarterly Report.pdf"), URL(fileURLWithPath: "/tmp/b.txt")]
        let plain = FolderPanel(apps: apps) { _ in }
        let withFiles = FolderPanel(apps: apps, files: files, handlers: { _ in [] }) { _ in }
        #expect(withFiles.frame.height == plain.frame.height + FolderPanel.headerHeight)
        #expect(withFiles.frame.width > plain.frame.width) // one-app grid widened for the title
        #expect(withFiles.frame.width <= FolderPanel.maxHeaderWidth)
        #expect(FolderPanel.header(for: files) == "Open 2 items with…")
        #expect(FolderPanel.header(for: [files[0]]) == "Open “Quarterly Report.pdf” with…")
    }

    @Test func handlersAreQueriedOncePerFileType() {
        let files = ["a.jpg", "b.jpg", "c.jpg", "d.txt"].map { URL(fileURLWithPath: "/tmp/\($0)") }
        var queries = 0
        let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
        let result = FolderPanel.appsAbleToOpen(files, type: { UTType(filenameExtension: $0.pathExtension)! }) { _ in
            queries += 1
            return [preview]
        }
        #expect(queries == 2)
        #expect(result == [preview.path])
        #expect(FolderPanel.appsAbleToOpen([], handlers: { _ in [] }) == nil)
        let many = (0..<(FolderPanel.maxTypesToCheck + 1)).map { URL(fileURLWithPath: "/tmp/f.ext\($0)") }
        #expect(FolderPanel.appsAbleToOpen(many, type: { UTType(filenameExtension: $0.pathExtension) ?? .item },
                                           handlers: { _ in [] }) == nil)
    }

    @Test func appsThatCantOpenDroppedFilesAreDimmed() throws {
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        try #require(FileManager.default.fileExists(atPath: calculator.path))
        try #require(FileManager.default.fileExists(atPath: textEdit.path))
        let panel = FolderPanel(apps: [calculator, textEdit], files: [URL(fileURLWithPath: "/tmp/a.txt")],
                                handlers: { _ in [textEdit] }) { _ in }
        let alphas = panel.contentView!.subviews.map(\.alphaValue)
        #expect(alphas.filter { $0 == FolderPanel.dimmedAlpha }.count == 1) // Calculator
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
