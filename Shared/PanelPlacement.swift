import CoreGraphics

enum DockEdge: Equatable {
    case bottom, left, right
}

/// Pure geometry for placing the folder grid next to the Dock. All rects are in
/// AppKit screen coordinates (origin bottom-left).
enum PanelPlacement {
    static let gap: CGFloat = 8          // space between Dock and panel
    static let margin: CGFloat = 4       // minimum space to screen edges
    static let insetThreshold: CGFloat = 8 // smaller insets mean the Dock is auto-hidden
    static let autoHideReach: CGFloat = 40 // auto-hidden Dock: assumed distance from mouse to Dock's inner edge

    // TODO: AX positioning — read the clicked tile's frame from the Dock's accessibility tree
    // and anchor to it instead of the mouse location.

    static func dockEdge(screen: CGRect, visible: CGRect, mouse: CGPoint) -> DockEdge {
        let insets: [(DockEdge, CGFloat)] = [
            (.bottom, visible.minY - screen.minY),
            (.left, visible.minX - screen.minX),
            (.right, screen.maxX - visible.maxX),
        ]
        if let widest = insets.max(by: { $0.1 < $1.1 }), widest.1 > insetThreshold {
            return widest.0
        }
        // Auto-hidden Dock: the mouse is on it, so pick the nearest edge.
        let distances: [(DockEdge, CGFloat)] = [
            (.bottom, mouse.y - screen.minY),
            (.left, mouse.x - screen.minX),
            (.right, screen.maxX - mouse.x),
        ]
        return distances.min(by: { $0.1 < $1.1 })!.0
    }

    static func origin(panelSize size: CGSize, mouse: CGPoint, screen: CGRect, visible: CGRect) -> CGPoint {
        var o: CGPoint
        switch dockEdge(screen: screen, visible: visible, mouse: mouse) {
        case .bottom:
            let line = visible.minY - screen.minY > insetThreshold ? visible.minY : mouse.y + autoHideReach
            o = CGPoint(x: mouse.x - size.width / 2, y: line + gap)
        case .left:
            let line = visible.minX - screen.minX > insetThreshold ? visible.minX : mouse.x + autoHideReach
            o = CGPoint(x: line + gap, y: mouse.y - size.height / 2)
        case .right:
            let line = screen.maxX - visible.maxX > insetThreshold ? visible.maxX : mouse.x - autoHideReach
            o = CGPoint(x: line - gap - size.width, y: mouse.y - size.height / 2)
        }
        // Clamp into the visible frame; if the panel is too big, pin to the left/bottom.
        o.x = max(visible.minX + margin, min(o.x, visible.maxX - margin - size.width))
        o.y = max(visible.minY + margin, min(o.y, visible.maxY - margin - size.height))
        return o
    }
}
