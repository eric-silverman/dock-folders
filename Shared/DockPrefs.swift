import Foundation

/// Reads and edits `persistent-apps` (the left side of the Dock) in com.apple.dock.
enum DockPrefs {
    typealias Tile = [String: Any]

    struct Unavailable: LocalizedError {
        var errorDescription: String? { "Couldn't read the Dock's app list, so it was left unchanged." }
    }

    static func path(of tile: Tile) -> String? {
        guard let data = tile["tile-data"] as? [String: Any],
              let file = data["file-data"] as? [String: Any],
              let string = file["_CFURLString"] as? String else { return nil }
        let url = (file["_CFURLStringType"] as? Int) == 15 ? URL(string: string) : URL(fileURLWithPath: string)
        return url?.standardizedFileURL.path
    }

    static func tile(for app: URL, label: String) -> Tile {
        [
            "tile-type": "file-tile",
            "tile-data": [
                "file-label": label,
                "file-type": 41,
                "file-data": ["_CFURLString": app.absoluteString, "_CFURLStringType": 15],
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
    static let backupURL = FolderStore.defaultURL.deletingLastPathComponent().appending(path: "persistent-apps-backup.plist")

    static func read() -> [Tile]? {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key, domain) as? [Tile]
    }

    static func paths() -> Set<String> {
        Set((read() ?? []).compactMap(path(of:)))
    }

    /// Applies `change` to the Dock's app list. Refuses to write if the list can't be read, so a
    /// failed read can never wipe the Dock. The previous list is saved to `backupURL` first.
    static func update(_ change: ([Tile]) -> [Tile]) throws {
        guard let tiles = read() else { throw Unavailable() }
        let updated = change(tiles)
        guard updated.count != tiles.count || !NSArray(array: updated).isEqual(to: tiles) else { return }
        try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: tiles, format: .xml, options: 0).write(to: backupURL, options: .atomic)
        CFPreferencesSetAppValue(key, updated as CFArray, domain)
        CFPreferencesAppSynchronize(domain)
    }

    static func restartDock() {
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["Dock"])
    }
}
