import AppKit

/// App icon without the alias badge NSWorkspace adds for symlinks such as /Applications/Safari.app.
func appIcon(forPath path: String) -> NSImage {
    NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
}
