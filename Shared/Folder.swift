import Foundation

struct Folder: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var appPaths: [String]
    var layout: FolderLayout = .grid
    var color: FolderColor = .graphite
}

extension Folder {
    // Display options are optional and lenient: a missing key (older file) or an unknown value (newer
    // file, typo) falls back to the default instead of failing the whole folders.json load.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        appPaths = try c.decode([String].self, forKey: .appPaths)
        layout = (try? c.decodeIfPresent(FolderLayout.self, forKey: .layout)) ?? .grid
        color = (try? c.decodeIfPresent(FolderColor.self, forKey: .color)) ?? .graphite
    }
}

/// How the popup shows the folder's apps.
enum FolderLayout: String, Codable, CaseIterable, Sendable {
    case grid, list
}

/// Background of the folder's Dock icon.
enum FolderColor: String, Codable, CaseIterable, Sendable {
    case graphite, blue, purple, pink, red, orange, yellow, green

    var displayName: String { rawValue.capitalized }

    /// Base sRGB color; the icon renders it as a gradient (lighter top, darker bottom).
    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .graphite: (0.32, 0.32, 0.34)
        case .blue: (0.16, 0.47, 0.96)
        case .purple: (0.55, 0.32, 0.85)
        case .pink: (0.93, 0.33, 0.58)
        case .red: (0.90, 0.26, 0.24)
        case .orange: (0.95, 0.55, 0.15)
        case .yellow: (0.95, 0.78, 0.18)
        case .green: (0.25, 0.70, 0.36)
        }
    }
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
