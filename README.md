# DockFolders

Folders of apps in the macOS Dock. Click a folder tile and a grid of its apps pops up; click one to launch it.

Each folder is a tiny generated app (`~/Applications/DockFolders/<Name>.app`) that shows the grid and quits.

## Build

Requires Xcode 16+ and macOS 15+.

```sh
xcodebuild -project DockFolders.xcodeproj -scheme DockFolders -derivedDataPath build build
open build/Build/Products/Debug/DockFolders.app
```

Or open `DockFolders.xcodeproj` in Xcode and run the **DockFolders** scheme. Tests: same `xcodebuild` command with `test`.

The Xcode project is generated from `project.yml`. After adding/removing files, run `xcodegen generate` and commit the result.

## Use

1. Launch DockFolders. Its window opens, and it lives in the menu bar (grid icon) after that.
2. Click **+** to create a folder, type a name, and press Return.
3. Drag apps in from Finder, or click **Add Apps…**. Drag rows to reorder.
4. Optional: choose **Grid** or **List** for how the folder opens, and a color for its Dock icon.
5. Click **Add to Dock**. After you confirm, the Dock restarts with the folder on the right side, next to Downloads, so folders stay apart from the running apps on the left. (Folders added to the left side by earlier versions keep working.)

Drop files on a folder in the Dock to open them: the folder shows "Open … with", dims apps that can't open them, and clicking an app opens the files in it. A dot marks apps in the folder that are already running; clicking one brings it to the front. App-list changes take effect the next time you open the folder. Changing a folder's first 9 apps rebuilds its icon. The Dock caches icons, so click **Refresh Dock** in the toolbar when it appears. Renaming a folder that's in the Dock restarts the Dock automatically; otherwise its tile would break.

**Delete Folder** moves the folder app to the Trash and takes it out of the Dock. The apps inside it aren't touched.

## Files

| Path | What |
|---|---|
| `~/Library/Application Support/DockFolders/folders.json` | Folder names and app lists |
| `~/Library/Application Support/DockFolders/persistent-{apps,others}-original.plist` | Each side of your Dock from before DockFolders first changed it (written once) |
| `~/Library/Application Support/DockFolders/persistent-{apps,others}-backup.plist` | Each side of your Dock from just before DockFolders last changed it |
| `~/Applications/DockFolders/*.app` | Generated folder apps (ad-hoc signed) |

## Known limitations

- **Icon caching:** after you change a folder's apps, the Dock can keep showing the old icon or name until it restarts (**Refresh Dock**).
- **Position:** the folder opens at the mouse pointer, above or beside the Dock, rather than lined up with the exact tile.
- **Signing:** DockFolders and its folder apps are signed with the Developer ID certificate in project.yml (macOS won't load the Dock menu plug-in from an ad-hoc signed app). Building on another Mac needs that certificate, or change `DEVELOPMENT_TEAM`/`CODE_SIGN_IDENTITY`; with ad-hoc signing everything works except the Dock right-click "Edit" item.
- **Running apps still get their own Dock icon:** macOS adds a Dock icon for every running app, and no public API lets another app hide it. The icon goes away when you quit the app (if "Show suggested and recent apps in Dock" is off).
- **Auto-hidden Dock:** the folder guesses which edge the Dock is on from where the mouse is.

## Layout

- `FolderStub/`: the per-folder app (the popup), built as "DockFolders Folder.app" and copied for each folder.
- `FolderDockMenu/`: Dock tile plug-in inside each folder app; adds "Edit “Name”…" to the Dock's right-click menu.
- `DockFolders/`: the manager app (UI, folder-app generation, icon rendering).
- `Shared/`: code used by both apps and the tests (config, plist rewriting, Dock prefs, panel positioning).
- `Tests/`: unit tests.
