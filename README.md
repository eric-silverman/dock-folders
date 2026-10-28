# DockFolders

Folders of apps on the **left (apps) side** of the macOS Dock. Click a folder tile and a grid of its apps pops up; click one to launch it.

The Dock only accepts apps on that side, so each folder is a tiny generated app (`~/Applications/DockFolders/<Name>.app`) that shows the grid and quits.

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
5. Click **Add to Dock**. After you confirm, the Dock restarts with the folder at the end of the apps side. To place it yourself, choose **Show in Finder Instead** and drag it into the Dock.

App-list changes take effect the next time you open the folder. Changing a folder's first 9 apps rebuilds its icon. The Dock caches icons, so click **Refresh Dock** in the toolbar when it appears. Renaming a folder that's in the Dock restarts the Dock automatically; otherwise its tile would break.

**Delete Folder** moves the folder app to the Trash and takes it out of the Dock. The apps inside it aren't touched.

## Files

| Path | What |
|---|---|
| `~/Library/Application Support/DockFolders/folders.json` | Folder names and app lists |
| `~/Library/Application Support/DockFolders/persistent-apps-original.plist` | Your Dock's app list from before DockFolders first changed it (written once) |
| `~/Library/Application Support/DockFolders/persistent-apps-backup.plist` | Your Dock's app list from just before DockFolders last changed it |
| `~/Applications/DockFolders/*.app` | Generated folder apps (ad-hoc signed) |

## Known limitations

- **Icon caching:** after you change a folder's apps, the Dock can keep showing the old icon or name until it restarts (**Refresh Dock**).
- **Position:** the grid opens at the mouse pointer, above or beside the Dock, rather than lined up with the exact tile.
- **Ad-hoc signing:** folder apps are signed locally and work on this Mac. Copying them to another Mac isn't supported.
- **Running apps still get their own Dock icon:** macOS adds a Dock icon for every running app, and no public API lets another app hide it. The icon goes away when you quit the app (if "Show suggested and recent apps in Dock" is off).
- **Auto-hidden Dock:** the grid guesses which edge the Dock is on from where the mouse is.

## Layout

- `FolderStub/`: the per-folder app (grid panel).
- `DockFolders/`: the manager app (UI, folder-app generation, icon rendering).
- `Shared/`: code used by both apps and the tests (config, plist rewriting, Dock prefs, panel positioning).
- `Tests/`: unit tests.
