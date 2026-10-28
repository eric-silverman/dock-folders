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

    private var scrollObserver: Any?

    init(apps: [URL], layout: FolderLayout = .grid, onPick: @escaping (URL) -> Void) {
        let n = max(apps.count, 1)
        let cols = min(Self.maxColumns, Int(Double(n).squareRoot().rounded(.up)))
        let rows = (n + cols - 1) / cols
        let list = layout == .list && !apps.isEmpty
        let listHeight = CGFloat(apps.count) * Self.row.height
        let size = list
            ? NSSize(width: Self.row.width + 2 * Self.listPadding,
                     height: min(listHeight, Self.maxListHeight) + 2 * Self.listPadding)
            : NSSize(width: CGFloat(cols) * Self.cell.width + 2 * Self.padding,
                     height: CGFloat(rows) * Self.cell.height + 2 * Self.padding)

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
        if list {
            let scroll = NSScrollView(frame: effect.bounds.insetBy(dx: Self.listPadding, dy: Self.listPadding))
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = listHeight > Self.maxListHeight
            // Rows fit beside a legacy ("Show scroll bars: Always") scroller instead of under it.
            let width = scroll.contentSize.width
            let listView = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: listHeight))
            for (i, url) in apps.enumerated() {
                let frame = NSRect(x: 0, y: CGFloat(i) * Self.row.height, width: width, height: Self.row.height)
                listView.addSubview(AppItemView(url: url, frame: frame, style: .row, onPick: onPick))
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
            effect.addSubview(AppItemView(url: url, frame: NSRect(origin: origin, size: Self.cell), style: .tile, onPick: onPick))
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

    init(url: URL, frame: NSRect, style: Style, onPick: @escaping (URL) -> Void) {
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
