import Foundation

/// Reads and edits the Dock's tile lists in com.apple.dock.
enum DockPrefs {
    typealias Tile = [String: Any]

    /// The Dock's two sections. Folder apps go on the right (`others`), next to Downloads, so they stay
    /// apart from the running apps on the left; folders added on the left by earlier versions still work.
    enum List: String, CaseIterable {
        case apps = "persistent-apps"     // left of the divider
        case others = "persistent-others" // right of the divider
    }

    // Values the Dock itself writes in its plist.
    static let urlStringTypeURL = 15 // _CFURLString holds a file:// URL (0 = plain path)
    static let fileTypeApp = 41

    struct Unavailable: LocalizedError {
        var errorDescription: String? {
            "Couldn't read the Dock's settings, so the Dock was left unchanged. Drag the folder from Finder into the Dock instead (Show in Finder)."
        }
    }

    struct WriteFailed: LocalizedError {
        var errorDescription: String? { "Couldn't save the Dock's settings." }
    }

    static func path(of tile: Tile) -> String? {
        guard let data = tile["tile-data"] as? [String: Any],
              let file = data["file-data"] as? [String: Any],
              let string = file["_CFURLString"] as? String else { return nil }
        let isURL = (file["_CFURLStringType"] as? Int) == urlStringTypeURL
        let url = isURL ? URL(string: string) : URL(fileURLWithPath: string)
        return url?.standardizedFileURL.path
    }

    static func tile(for app: URL, label: String) -> Tile {
        [
            "tile-type": "file-tile",
            "tile-data": [
                "file-label": label,
                "file-type": fileTypeApp,
                "file-data": ["_CFURLString": app.absoluteString, "_CFURLStringType": urlStringTypeURL],
            ],
        ]
    }

    static func adding(_ app: URL, label: String, to tiles: [Tile]) -> [Tile] {
        let p = app.standardizedFileURL.path
        return tiles.contains { path(of: $0) == p } ? tiles : tiles + [tile(for: app, label: label)]
    }

    static func removing(_ app: URL, from tiles: [Tile]) -> [Tile] {
        let p = app.standardizedFileURL.path
        return tiles.filter { path(of: $0) != p }
    }

    static func replacing(_ old: URL, with new: URL, label: String, in tiles: [Tile]) -> [Tile] {
        let p = old.standardizedFileURL.path
        return tiles.map { path(of: $0) == p ? tile(for: new, label: label) : $0 }
    }

    // MARK: - I/O

    private static var domain: CFString { "com.apple.dock" as CFString }
    static let backupDirectory = FolderStore.defaultURL.deletingLastPathComponent()

    /// nil if the list is missing or unreadable. A missing list is not treated as empty: on a fresh account
    /// the Dock shows built-in defaults (Downloads) without storing them, and writing would drop those.
    static func read(_ list: List) -> [Tile]? {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(list.rawValue as CFString, domain) as? [Tile]
    }

    static func write(_ tiles: [Tile], to list: List) -> Bool {
        CFPreferencesSetAppValue(list.rawValue as CFString, tiles as CFArray, domain)
        return CFPreferencesAppSynchronize(domain)
    }

    /// Paths of every file tile on either side of the Dock.
    static func paths() -> Set<String> {
        Set(List.allCases.flatMap { read($0) ?? [] }.compactMap(path(of:)))
    }

    /// Applies `change` to one of the Dock's lists. Returns whether anything was written.
    /// Refuses to write if the list can't be read, so a failed read can never wipe the Dock.
    /// Before writing it saves the current list as the latest backup, plus a one-time backup of
    /// the list from before DockFolders first touched it.
    @discardableResult
    static func update(_ list: List, read: (() -> [Tile]?)? = nil, write: (([Tile]) -> Bool)? = nil,
                       backupDirectory: URL = DockPrefs.backupDirectory, _ change: ([Tile]) -> [Tile]) throws -> Bool {
        guard let tiles = read.map({ $0() }) ?? Self.read(list) else { throw Unavailable() }
        let updated = change(tiles)
        guard !NSArray(array: updated).isEqual(to: tiles) else { return false }

        let fm = FileManager.default
        try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: tiles, format: .xml, options: 0)
        let original = backupDirectory.appending(path: "\(list.rawValue)-original.plist")
        if !fm.fileExists(atPath: original.path) { try data.write(to: original, options: .atomic) }
        try data.write(to: backupDirectory.appending(path: "\(list.rawValue)-backup.plist"), options: .atomic)

        guard write.map({ $0(updated) }) ?? Self.write(updated, to: list) else { throw WriteFailed() }
        return true
    }

    static func restartDock() {
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["Dock"])
    }
}
