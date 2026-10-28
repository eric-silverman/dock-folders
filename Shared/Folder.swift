import Foundation

struct Folder: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var appPaths: [String]
}

enum FolderStore {
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/DockFolders/folders.json")

    /// Missing file means no folders yet; a corrupt file throws.
    static func load(from url: URL = defaultURL) throws -> [Folder] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([Folder].self, from: Data(contentsOf: url))
    }

    static func save(_ folders: [Folder], to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(folders).write(to: url, options: .atomic)
    }
}

/// Info.plist changes that turn the FolderStub template into one folder's app.
enum StubInfo {
    static let folderIDKey = "DockFolderID"
    static let iconName = "FolderIcon"

    static func rewrite(_ plist: [String: Any], folder: Folder, managerBundleID: String) -> [String: Any] {
        var p = plist
        p["CFBundleIdentifier"] = "\(managerBundleID).folder.\(folder.id.uuidString)"
        p["CFBundleName"] = folder.name
        p["CFBundleDisplayName"] = folder.name
        p[folderIDKey] = folder.id.uuidString
        p["CFBundleIconFile"] = iconName
        p.removeValue(forKey: "CFBundleIconName") // an asset-catalog icon would win over the .icns
        return p
    }
}
