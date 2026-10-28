import AppKit
import QuartzCore

/// Borderless vibrant popup of a folder's apps: a Dock-stack-style icon grid, or a compact list.
final class FolderPanel: NSPanel {
    static let cell = NSSize(width: 96, height: 96)
    static let padding: CGFloat = 12
    static let maxColumns = 6
    static let row = NSSize(width: 260, height: 30)
    static let listPadding: CGFloat = 6
    static let maxListHeight: CGFloat = 480     // taller lists scroll
    static let rise: CGFloat = 12              // open animation: distance the popup slides out of the Dock
    static let openDuration: TimeInterval = 0.12
    static let headerHeight: CGFloat = 28      // "Open … with" title when files were dropped on the folder

    private var scrollObserver: Any?

    /// Canonical path for comparing an app in the folder with a running app (e.g. /Applications/Safari.app
    /// is a symlink into the system cryptex).
    static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func runningAppPaths(_ bundleURLs: [URL?]) -> Set<String> {
        Set(bundleURLs.compactMap { $0.map(canonicalPath) })
    }

    /// Apps that can open every one of the files, given each file's handler list from Launch Services.
    static func appsAbleToOpenAll(_ handlersPerFile: [[URL]]) -> Set<String> {
        guard let first = handlersPerFile.first else { return [] }
        return handlersPerFile.dropFirst().reduce(Set(first.map(canonicalPath))) { $0.intersection($1.map(canonicalPath)) }
    }

    static func header(for files: [URL]) -> String {
        files.count == 1 ? "Open “\(FileManager.default.displayName(atPath: files[0].path))” with…"
                         : "Open \(files.count) items with…"
    }

    init(apps: [URL], layout: FolderLayout = .grid, files: [URL] = [], onPick: @escaping (URL) -> Void) {
        let n = max(apps.count, 1)
        let cols = min(Self.maxColumns, Int(Double(n).squareRoot().rounded(.up)))
        let rows = (n + cols - 1) / cols
        let list = layout == .list && !apps.isEmpty
        // Regular apps only (what the Dock shows); skips ~100 helpers and agents on the open path.
        let running = Self.runningAppPaths(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }.map(\.bundleURL))
        // Dropped files: dim apps Launch Services says can't open them (still clickable; declarations are
        // incomplete for some apps).
        let canOpen: Set<String>? = files.isEmpty ? nil
            : Self.appsAbleToOpenAll(files.map { NSWorkspace.shared.urlsForApplications(toOpen: $0) })
        let header: CGFloat = files.isEmpty ? 0 : Self.headerHeight
        let listHeight = CGFloat(apps.count) * Self.row.height
        var size = list
            ? NSSize(width: Self.row.width + 2 * Self.listPadding,
                     height: min(listHeight, Self.maxListHeight) + 2 * Self.listPadding)
            : NSSize(width: CGFloat(cols) * Self.cell.width + 2 * Self.padding,
                     height: CGFloat(rows) * Self.cell.height + 2 * Self.padding)
        size.height += header

        // Non-activating: macOS won't let a Dock-launched UI-element app take focus, and a regular panel
        // hides while its app is inactive. This one shows anyway and can still be key (for Escape).
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = NSImage(size: size, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()
            return true
        }
        contentView = effect

        if apps.isEmpty {
            let label = NSTextField(labelWithString: "No apps")
            label.textColor = .secondaryLabelColor
            label.sizeToFit()
            label.setFrameOrigin(NSPoint(x: (size.width - label.frame.width) / 2,
                                         y: (size.height - label.frame.height) / 2))
            effect.addSubview(label)
        }
        if !files.isEmpty {
            let title = NSTextField(labelWithString: Self.header(for: files))
            title.font = .systemFont(ofSize: 12, weight: .semibold)
            title.textColor = .secondaryLabelColor
            title.lineBreakMode = .byTruncatingMiddle
            title.frame = NSRect(x: 12, y: size.height - header + 2, width: size.width - 24, height: header - 10)
            effect.addSubview(title)
        }
        func dimmed(_ url: URL) -> Bool { canOpen.map { !$0.contains(Self.canonicalPath(url)) } ?? false }
        if list {
            let scroll = NSScrollView(frame: NSRect(x: Self.listPadding, y: Self.listPadding,
                                                    width: size.width - 2 * Self.listPadding,
                                                    height: size.height - header - 2 * Self.listPadding))
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = listHeight > Self.maxListHeight
            // Rows fit beside a legacy ("Show scroll bars: Always") scroller instead of under it.
            let width = scroll.contentSize.width
            let listView = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: listHeight))
            for (i, url) in apps.enumerated() {
                let frame = NSRect(x: 0, y: CGFloat(i) * Self.row.height, width: width, height: Self.row.height)
                listView.addSubview(AppItemView(url: url, frame: frame, style: .row,
                                                running: running.contains(Self.canonicalPath(url)),
                                                dimmed: dimmed(url), onPick: onPick))
            }
            scroll.documentView = listView
            effect.addSubview(scroll)
            // Scrolling under a still pointer sends no enter/exit events, so re-check hover on scroll.
            scroll.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { _ in
                MainActor.assumeIsolated {
                    for case let item as AppItemView in listView.subviews { item.updateHover() }
                }
            }
            return
        }
        for (i, url) in apps.enumerated() {
            let row = i / cols, col = i % cols
            let origin = NSPoint(x: Self.padding + CGFloat(col) * Self.cell.width,
                                 y: Self.padding + CGFloat(rows - 1 - row) * Self.cell.height)
            effect.addSubview(AppItemView(url: url, frame: NSRect(origin: origin, size: Self.cell), style: .tile,
                                          running: running.contains(Self.canonicalPath(url)),
                                          dimmed: dimmed(url), onPick: onPick))
        }
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { NSApp.terminate(nil) } else { super.keyDown(with: event) } // Escape
    }

    /// Places the popup next to the Dock and animates it in: a short fade while sliding out of the Dock edge.
    func show(near mouse: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
            center()
            return makeKeyAndOrderFront(nil)
        }
        let final = NSRect(origin: PanelPlacement.origin(panelSize: frame.size, mouse: mouse,
                                                         screen: screen.frame, visible: screen.visibleFrame),
                           size: frame.size)
        let d = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Self.rise
        let start = switch PanelPlacement.dockEdge(screen: screen.frame, visible: screen.visibleFrame, mouse: mouse) {
        case .bottom: final.offsetBy(dx: 0, dy: -d)
        case .left: final.offsetBy(dx: -d, dy: 0)
        case .right: final.offsetBy(dx: d, dy: 0)
        }
        setFrame(start, display: false)
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.openDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(final, display: true)
            animator().alphaValue = 1
        }
    }
}

/// Top-to-bottom coordinates, so list rows start at the top of the scroll view.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class AppItemView: NSView {
    enum Style { case tile, row }

    private let url: URL
    private let available: Bool
    private let onPick: (URL) -> Void

    init(url: URL, frame: NSRect, style: Style, running: Bool, dimmed: Bool = false, onPick: @escaping (URL) -> Void) {
        self.url = url
        self.onPick = onPick
        available = FileManager.default.fileExists(atPath: url.path)
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = style == .tile ? 8 : 6

        let icon = NSImageView()
        icon.image = appIcon(forPath: url.path)
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)

        let name = available ? FileManager.default.displayName(atPath: url.path)
                             : url.deletingPathExtension().lastPathComponent
        let label = NSTextField(labelWithString: name)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        switch style {
        case .tile:
            icon.frame = NSRect(x: (frame.width - 64) / 2, y: 26, width: 64, height: 64)
            label.font = .systemFont(ofSize: 11)
            label.alignment = .center
            label.frame = NSRect(x: 4, y: 6, width: frame.width - 8, height: 16)
        case .row:
            let inset: CGFloat = 6, iconSize: CGFloat = 24, gap: CGFloat = 8
            icon.frame = NSRect(x: inset, y: (frame.height - iconSize) / 2, width: iconSize, height: iconSize)
            label.font = .systemFont(ofSize: 13)
            label.sizeToFit()
            let labelX = inset + iconSize + gap
            label.frame = NSRect(x: labelX, y: (frame.height - label.frame.height) / 2,
                                 width: frame.width - labelX - inset, height: label.frame.height)
        }

        // Running indicator, like the Dock's: under the icon in the grid, left of it in the list.
        if running {
            let size: CGFloat = 4
            let dot = NSView(frame: style == .tile
                ? NSRect(x: (frame.width - size) / 2, y: icon.frame.minY - size, width: size, height: size)
                : NSRect(x: 1, y: (frame.height - size) / 2, width: size, height: size))
            dot.wantsLayer = true
            dot.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.7).cgColor
            dot.layer?.cornerRadius = size / 2
            addSubview(dot)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(running ? "\(name), running" : name)

        if available && dimmed {
            alphaValue = 0.45
            toolTip = "\(name) may not open this"
        }
        if !available {
            alphaValue = 0.35
            toolTip = "Not found: \(url.path)"
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    // Swallow clicks on subviews so the whole cell is the hit target.
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) { setHighlighted(true) }
    override func mouseExited(with event: NSEvent) { setHighlighted(false) }

    func updateHover() {
        guard let window else { return }
        setHighlighted(bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)))
    }

    private func setHighlighted(_ on: Bool) {
        layer?.backgroundColor = on && available ? NSColor.labelColor.withAlphaComponent(0.12).cgColor : nil
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard available, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPick(url)
    }
}
