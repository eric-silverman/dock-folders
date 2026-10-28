import AppKit

/// Loaded by the Dock from inside each folder app (Contents/PlugIns), so the folder's right-click menu can
/// offer "Edit Folder…" even though the folder app isn't running.
@objc(DockMenuPlugIn)
final class DockMenuPlugIn: NSObject, NSDockTilePlugIn {
    /// The folder app containing this plug-in: <Folder>.app/Contents/PlugIns/FolderDockMenu.docktileplugin
    private var folderApp: Bundle? {
        Bundle(url: Bundle(for: DockMenuPlugIn.self).bundleURL
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
    }

    func setDockTile(_ dockTile: NSDockTile?) {}

    func dockMenu() -> NSMenu? {
        let name = folderApp?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let item = NSMenuItem(title: name.map { "Edit “\($0)”…" } ?? "Edit Folder…",
                              action: #selector(editFolder), keyEquivalent: "")
        item.target = self
        let menu = NSMenu()
        menu.addItem(item)
        return menu
    }

    @objc private func editFolder() {
        guard let app = folderApp, let appID = app.bundleIdentifier,
              let id = (app.object(forInfoDictionaryKey: StubInfo.folderIDKey) as? String).flatMap(UUID.init(uuidString:))
        else { return }
        ManagerRequest.edit.send(folderID: id, folderAppBundleID: appID)
    }
}
