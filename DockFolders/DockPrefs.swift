import Foundation

/// Reads and edits `persistent-apps` (the left side of the Dock) in com.apple.dock.
enum DockPrefs {
    typealias Tile = [String: Any]

    // Values the Dock itself writes in its plist.
    static let urlStringTypeURL = 15 // _CFURLString holds a file:// URL (0 = plain path)
    static let fileTypeApp = 41

    struct Unavailable: LocalizedError {
        var errorDescription: String? { "Couldn't read the Dock's app list, so it was left unchanged." }
    }

    struct WriteFailed: LocalizedError {
        var errorDescription: String? { "Couldn't save the Dock's app list." }
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
    private static var key: CFString { "persistent-apps" as CFString }
    static let backupDirectory = FolderStore.defaultURL.deletingLastPathComponent()

    static func read() -> [Tile]? {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key, domain) as? [Tile]
    }

    static func write(_ tiles: [Tile]) -> Bool {
        CFPreferencesSetAppValue(key, tiles as CFArray, domain)
        return CFPreferencesAppSynchronize(domain)
    }

    static func paths() -> Set<String> {
        Set((read() ?? []).compactMap(path(of:)))
    }

    /// Applies `change` to the Dock's app list. Returns whether anything was written.
    /// Refuses to write if the list can't be read, so a failed read can never wipe the Dock.
    /// Before writing it saves the current list as the latest backup, plus a one-time backup of
    /// the list from before DockFolders first touched the Dock.
    @discardableResult
    static func update(read: () -> [Tile]? = DockPrefs.read, write: ([Tile]) -> Bool = DockPrefs.write,
                       backupDirectory: URL = DockPrefs.backupDirectory, _ change: ([Tile]) -> [Tile]) throws -> Bool {
        guard let tiles = read() else { throw Unavailable() }
        let updated = change(tiles)
        guard !NSArray(array: updated).isEqual(to: tiles) else { return false }

        let fm = FileManager.default
        try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: tiles, format: .xml, options: 0)
        let original = backupDirectory.appending(path: "persistent-apps-original.plist")
        if !fm.fileExists(atPath: original.path) { try data.write(to: original, options: .atomic) }
        try data.write(to: backupDirectory.appending(path: "persistent-apps-backup.plist"), options: .atomic)

        guard write(updated) else { throw WriteFailed() }
        return true
    }

    static func restartDock() {
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["Dock"])
    }
}
