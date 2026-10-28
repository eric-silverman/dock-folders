import Foundation
import Testing

struct FolderStoreTests {
    @Test func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "DockFoldersTests-\(UUID())/folders.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let folders = [
            Folder(id: UUID(), name: "Dev", appPaths: ["/Applications/Xcode.app", "/System/Applications/Utilities/Terminal.app"]),
            Folder(id: UUID(), name: "Empty", appPaths: []),
            Folder(id: UUID(), name: "Styled", appPaths: [], layout: .list, color: .purple),
        ]
        try FolderStore.save(folders, to: url)
        #expect(try FolderStore.load(from: url) == folders)
    }

    @Test func olderFilesWithoutDisplayOptionsStillLoad() throws {
        let json = #"[{"id":"11111111-2222-3333-4444-555555555555","name":"Old","appPaths":["/Applications/Safari.app"]}]"#
        let folder = try JSONDecoder().decode([Folder].self, from: Data(json.utf8))[0]
        #expect(folder.name == "Old")
        #expect(folder.layout == .grid)
        #expect(folder.color == .graphite)
    }

    @Test func unknownDisplayOptionValuesFallBackToDefaults() throws {
        let json = #"[{"id":"11111111-2222-3333-4444-555555555555","name":"New","appPaths":[],"layout":"fan","color":"teal"}]"#
        let folder = try JSONDecoder().decode([Folder].self, from: Data(json.utf8))[0]
        #expect(folder.layout == .grid)
        #expect(folder.color == .graphite)
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

struct DroppedAppsTests {
    @Test func addAppsSkipsNonAppsAndDuplicates() {
        var folder = Folder(id: UUID(), name: "F", appPaths: ["/Applications/A.app"])
        let added = folder.addApps(["/Applications/A.app", "/Applications/B.app", "/tmp/notes.txt", "/Applications/B.app"]
            .map { URL(fileURLWithPath: $0) })
        #expect(added == ["/Applications/B.app"])
        #expect(folder.appPaths == ["/Applications/A.app", "/Applications/B.app"])
    }

    @Test func storeUpdateChangesOneFolder() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "DockFoldersTests-\(UUID())/folders.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let a = Folder(id: UUID(), name: "A", appPaths: []), b = Folder(id: UUID(), name: "B", appPaths: [])
        try FolderStore.save([a, b], to: url)
        #expect(try FolderStore.update(b.id, at: url) { $0.addApps([URL(fileURLWithPath: "/Applications/X.app")]) })
        #expect(try FolderStore.load(from: url).map(\.appPaths) == [[], ["/Applications/X.app"]])
        #expect(try FolderStore.update(UUID(), at: url) { _ in } == false)
    }

    @Test func requestArgumentsRoundTrip() {
        let id = UUID()
        let args = ["DockFolders", StubInfo.backgroundArgument, ManagerRequest.rebuild.argument, id.uuidString]
        #expect(ManagerRequest.rebuild.folderID(in: args) == id)
        #expect(ManagerRequest.edit.folderID(in: args) == nil)
        #expect(ManagerRequest.edit.folderID(in: ["DockFolders", "--edit"]) == nil)
        #expect(ManagerRequest.edit.notificationName(managerBundleID: "m").rawValue == "m.edit")
    }

    @Test func managerIDFromFolderAppID() {
        #expect(StubInfo.managerBundleID(fromStubID: "com.esilverman.DockFolders.folder.11111111-2222-3333-4444-555555555555")
                == "com.esilverman.DockFolders")
        #expect(StubInfo.managerBundleID(fromStubID: "com.esilverman.DockFolders.FolderStub") == nil)
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

struct DockPrefsEdgeTests {
    let stub = URL(fileURLWithPath: "/Users/me/Applications/DockFolders/Dev Tools.app", isDirectory: true)

    @Test func spacersAndPlainPathTilesSurvive() {
        let spacer: DockPrefs.Tile = ["tile-type": "spacer-tile", "tile-data": [String: Any]()]
        let plain: DockPrefs.Tile = ["tile-data": ["file-data": ["_CFURLString": "/Applications/Safari.app", "_CFURLStringType": 0]]]
        #expect(DockPrefs.path(of: plain) == "/Applications/Safari.app")
        let tiles = DockPrefs.adding(stub, label: "Dev Tools", to: [spacer, plain])
        #expect(tiles.count == 3)
        #expect(DockPrefs.removing(stub, from: tiles).count == 2)
        #expect(DockPrefs.replacing(stub, with: stub, label: "x", in: tiles).count == 3)
    }

    @Test func updateRefusesWhenDockUnreadable() {
        var wrote = false
        #expect(throws: DockPrefs.Unavailable.self) {
            try DockPrefs.update(.apps, read: { nil }, write: { _ in wrote = true; return true },
                                 backupDirectory: tempDir()) { $0 + [[:]] }
        }
        #expect(!wrote)
    }

    @Test func updateSkipsNoOpAndKeepsOriginalBackup() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var dock: [DockPrefs.Tile] = [DockPrefs.tile(for: URL(fileURLWithPath: "/Applications/Safari.app", isDirectory: true), label: "Safari")]
        let read = { Optional(dock) }
        let write = { (t: [DockPrefs.Tile]) -> Bool in dock = t; return true }

        #expect(try DockPrefs.update(.apps, read: read, write: write, backupDirectory: dir) { $0 } == false)
        #expect(!FileManager.default.fileExists(atPath: dir.path))

        try DockPrefs.update(.apps, read: read, write: write, backupDirectory: dir) { DockPrefs.adding(stub, label: "Dev", to: $0) }
        try DockPrefs.update(.apps, read: read, write: write, backupDirectory: dir) { DockPrefs.removing(stub, from: $0) }
        let original = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: dir.appending(path: "\(DockPrefs.List.apps.rawValue)-original.plist")), format: nil) as? [Any]
        let latest = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: dir.appending(path: "\(DockPrefs.List.apps.rawValue)-backup.plist")), format: nil) as? [Any]
        #expect(original?.count == 1) // pre-DockFolders Dock, never overwritten
        #expect(latest?.count == 2)   // state just before the last write
    }

    @Test func eachListKeepsItsOwnBackups() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var right: [DockPrefs.Tile] = []
        try DockPrefs.update(.others, read: { right }, write: { right = $0; return true }, backupDirectory: dir) {
            DockPrefs.adding(stub, label: "Dev", to: $0)
        }
        #expect(right.compactMap(DockPrefs.path(of:)) == [stub.path])
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "\(DockPrefs.List.others.rawValue)-original.plist").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "\(DockPrefs.List.apps.rawValue)-original.plist").path))
    }

    @Test func renameAndDeleteCleanBothSides() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let safari = DockPrefs.tile(for: URL(fileURLWithPath: "/Applications/Safari.app", isDirectory: true), label: "Safari")
        var dock: [DockPrefs.List: [DockPrefs.Tile]] = [
            .apps: [safari, DockPrefs.tile(for: stub, label: "Dev")], // left, from an older version
            .others: [DockPrefs.tile(for: stub, label: "Dev")],        // and right
        ]
        func each(_ change: ([DockPrefs.Tile]) -> [DockPrefs.Tile]) throws {
            for list in DockPrefs.List.allCases {
                try DockPrefs.update(list, read: { dock[list] }, write: { dock[list] = $0; return true },
                                     backupDirectory: dir, change)
            }
        }
        let renamed = URL(fileURLWithPath: "/Users/me/Applications/DockFolders/Code.app", isDirectory: true)
        try each { DockPrefs.replacing(stub, with: renamed, label: "Code", in: $0) }
        #expect(dock[.apps]!.compactMap(DockPrefs.path(of:)) == ["/Applications/Safari.app", renamed.path])
        #expect(dock[.others]!.compactMap(DockPrefs.path(of:)) == [renamed.path])

        try each { DockPrefs.removing(renamed, from: $0) }
        #expect(dock[.apps]!.compactMap(DockPrefs.path(of:)) == ["/Applications/Safari.app"])
        #expect(dock[.others]!.isEmpty)
    }

    @Test func updateThrowsWhenWriteFails() {
        #expect(throws: DockPrefs.WriteFailed.self) {
            try DockPrefs.update(.apps, read: { [] }, write: { _ in false }, backupDirectory: tempDir()) { $0 + [[:]] }
        }
    }

    func tempDir() -> URL { FileManager.default.temporaryDirectory.appending(path: "DockFoldersTests-\(UUID())") }
}

struct StubGeneratorTests {
    @Test(arguments: [
        ("Dev Tools", "Dev Tools"), ("Dev/Tools", "Dev-Tools"), ("a:b", "a-b"),
        (".hidden", "_hidden"), ("../x", "_.-x"),
        ("Cafe\u{301}", "Café"), // decomposed é normalizes to precomposed
    ])
    func fileNameIsSafe(_ input: String, _ expected: String) {
        #expect(StubGenerator.fileName(for: input) == expected)
        #expect(StubGenerator.url(for: input).deletingLastPathComponent().path == StubGenerator.directory.path)
    }

    @Test func iconGridSizesToAppCount() {
        let r = CGRect(x: 0, y: 0, width: 90, height: 90)
        #expect(FolderIcon.cells(count: 0, in: r).isEmpty)
        #expect(FolderIcon.cells(count: 1, in: r) == [r])
        let four = FolderIcon.cells(count: 4, in: r)
        #expect(four == [CGRect(x: 0, y: 45, width: 45, height: 45), CGRect(x: 45, y: 45, width: 45, height: 45),
                         CGRect(x: 0, y: 0, width: 45, height: 45), CGRect(x: 45, y: 0, width: 45, height: 45)])
        // 3 apps: 2×2 with the lone bottom icon centered.
        #expect(FolderIcon.cells(count: 3, in: r)[2] == CGRect(x: 22.5, y: 0, width: 45, height: 45))
        let nine = FolderIcon.cells(count: 9, in: r)
        #expect(nine.count == 9 && nine.allSatisfy { r.contains($0) && $0.width == 30 })
        // 5 apps: 3 on top, 2 centered below, both rows centered vertically.
        let five = FolderIcon.cells(count: 5, in: r)
        #expect(five[0] == CGRect(x: 0, y: 45, width: 30, height: 30))
        #expect(five[3] == CGRect(x: 15, y: 15, width: 30, height: 30))
    }

    @Test func iconColorReachesRenderer() {
        #expect(FolderIcon.icns(appPaths: [], color: .red) != FolderIcon.icns(appPaths: [], color: .blue))
    }

    @Test func icnsContainerIsWellFormed() {
        let data = FolderIcon.icns(appPaths: [])
        #expect(data.prefix(4) == Data("icns".utf8))
        func u32(_ at: Int) -> Int { data[at..<at + 4].reduce(0) { $0 << 8 | Int($1) } }
        #expect(u32(4) == data.count)
        var offset = 8, types: [String] = []
        while offset < data.count {
            types.append(String(decoding: data[offset..<offset + 4], as: UTF8.self))
            offset += u32(offset + 4)
        }
        #expect(offset == data.count)
        #expect(types == FolderIcon.slots.map(\.0))
    }
}
