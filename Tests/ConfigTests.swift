import Foundation
import Testing

struct FolderStoreTests {
    @Test func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "DockFoldersTests-\(UUID())/folders.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let folders = [
            Folder(id: UUID(), name: "Dev", appPaths: ["/Applications/Xcode.app", "/System/Applications/Utilities/Terminal.app"]),
            Folder(id: UUID(), name: "Empty", appPaths: []),
        ]
        try FolderStore.save(folders, to: url)
        #expect(try FolderStore.load(from: url) == folders)
    }

    @Test func missingFileIsEmpty() throws {
        #expect(try FolderStore.load(from: URL(fileURLWithPath: "/nonexistent/folders.json")).isEmpty)
    }

    @Test func corruptFileThrows() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "DockFoldersTests-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        #expect(throws: (any Error).self) { try FolderStore.load(from: url) }
    }
}

struct StubInfoTests {
    @Test func rewritesIdentityNameAndIcon() {
        let folder = Folder(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!, name: "Dev Tools", appPaths: [])
        let template: [String: Any] = [
            "CFBundleIdentifier": "com.esilverman.DockFolders.FolderStub",
            "CFBundleName": "Folder",
            "CFBundleExecutable": "FolderStub",
            "CFBundleIconName": "AppIcon",
            "LSUIElement": true,
            "DockFolderID": "",
        ]
        let p = StubInfo.rewrite(template, folder: folder, managerBundleID: "com.esilverman.DockFolders")
        #expect(p["CFBundleIdentifier"] as? String == "com.esilverman.DockFolders.folder.11111111-2222-3333-4444-555555555555")
        #expect(p["CFBundleName"] as? String == "Dev Tools")
        #expect(p["CFBundleDisplayName"] as? String == "Dev Tools")
        #expect(p["DockFolderID"] as? String == "11111111-2222-3333-4444-555555555555")
        #expect(p["CFBundleIconFile"] as? String == "FolderIcon")
        #expect(p["CFBundleIconName"] == nil)
        // Untouched keys survive.
        #expect(p["CFBundleExecutable"] as? String == "FolderStub")
        #expect(p["LSUIElement"] as? Bool == true)
    }
}

struct DockPrefsTests {
    let stub = URL(fileURLWithPath: "/Users/me/Applications/DockFolders/Dev Tools.app", isDirectory: true)
    let other: DockPrefs.Tile = DockPrefs.tile(for: URL(fileURLWithPath: "/Applications/Safari.app", isDirectory: true), label: "Safari")

    @Test func tilePathRoundTrips() {
        #expect(DockPrefs.path(of: DockPrefs.tile(for: stub, label: "Dev Tools")) == stub.path)
    }

    @Test func addIsIdempotentAndKeepsExisting() {
        let once = DockPrefs.adding(stub, label: "Dev Tools", to: [other])
        #expect(once.count == 2)
        #expect(DockPrefs.path(of: once[0]) == "/Applications/Safari.app")
        #expect(DockPrefs.adding(stub, label: "Dev Tools", to: once).count == 2)
    }

    @Test func removeAndReplaceTouchOnlyTheStub() {
        let tiles = DockPrefs.adding(stub, label: "Dev Tools", to: [other])
        #expect(DockPrefs.removing(stub, from: tiles).compactMap(DockPrefs.path(of:)) == ["/Applications/Safari.app"])
        let renamed = URL(fileURLWithPath: "/Users/me/Applications/DockFolders/Code.app", isDirectory: true)
        let replaced = DockPrefs.replacing(stub, with: renamed, label: "Code", in: tiles)
        #expect(replaced.compactMap(DockPrefs.path(of:)) == ["/Applications/Safari.app", renamed.path])
    }
}
