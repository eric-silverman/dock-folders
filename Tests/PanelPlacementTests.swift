import CoreGraphics
import Testing

struct PanelPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let size = CGSize(width: 300, height: 200)

    // Menu bar takes 25pt at the top in every case.
    func visible(bottom: CGFloat = 0, left: CGFloat = 0, right: CGFloat = 0) -> CGRect {
        CGRect(x: left, y: bottom, width: 1440 - left - right, height: 900 - 25 - bottom)
    }

    @Test func dockBottom() {
        let v = visible(bottom: 70)
        let o = PanelPlacement.origin(panelSize: size, mouse: CGPoint(x: 700, y: 35), screen: screen, visible: v)
        #expect(o == CGPoint(x: 550, y: 70 + PanelPlacement.gap))
    }

    @Test func dockLeft() {
        let v = visible(left: 70)
        let o = PanelPlacement.origin(panelSize: size, mouse: CGPoint(x: 35, y: 450), screen: screen, visible: v)
        #expect(o == CGPoint(x: 70 + PanelPlacement.gap, y: 350))
    }

    @Test func dockRight() {
        let v = visible(right: 70)
        let o = PanelPlacement.origin(panelSize: size, mouse: CGPoint(x: 1405, y: 450), screen: screen, visible: v)
        #expect(o == CGPoint(x: 1370 - PanelPlacement.gap - 300, y: 350))
    }

    @Test func clampsAtScreenEdges() {
        let v = visible(bottom: 70)
        let m = PanelPlacement.margin
        let nearLeft = PanelPlacement.origin(panelSize: size, mouse: CGPoint(x: 20, y: 35), screen: screen, visible: v)
        #expect(nearLeft.x == m)
        let nearRight = PanelPlacement.origin(panelSize: size, mouse: CGPoint(x: 1430, y: 35), screen: screen, visible: v)
        #expect(nearRight.x == 1440 - m - 300)

        let side = visible(left: 70)
        let nearTop = PanelPlacement.origin(panelSize: size, mouse: CGPoint(x: 35, y: 870), screen: screen, visible: side)
        #expect(nearTop.y == 875 - m - 200)
        let nearBottom = PanelPlacement.origin(panelSize: size, mouse: CGPoint(x: 35, y: 10), screen: screen, visible: side)
        #expect(nearBottom.y == m)
    }

    @Test func oversizedPanelPinsToBottomLeft() {
        let v = visible(bottom: 70)
        let huge = CGSize(width: 2000, height: 2000)
        let o = PanelPlacement.origin(panelSize: huge, mouse: CGPoint(x: 700, y: 35), screen: screen, visible: v)
        #expect(o == CGPoint(x: PanelPlacement.margin, y: 70 + PanelPlacement.margin))
    }

    @Test func autoHiddenDockUsesNearestEdge() {
        let v = visible(bottom: 4)
        #expect(PanelPlacement.dockEdge(screen: screen, visible: v, mouse: CGPoint(x: 700, y: 30)) == .bottom)
        #expect(PanelPlacement.dockEdge(screen: screen, visible: visible(left: 4), mouse: CGPoint(x: 30, y: 450)) == .left)
        #expect(PanelPlacement.dockEdge(screen: screen, visible: visible(right: 4), mouse: CGPoint(x: 1410, y: 450)) == .right)
        let o = PanelPlacement.origin(panelSize: size, mouse: CGPoint(x: 700, y: 30), screen: screen, visible: v)
        #expect(o.y == 30 + PanelPlacement.autoHideReach + PanelPlacement.gap)
    }

    @Test func secondaryScreenOffset() {
        // Screen to the right of the main one, Dock at its bottom.
        let s = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let v = CGRect(x: 1440, y: 70, width: 1920, height: 1080 - 25 - 70)
        let o = PanelPlacement.origin(panelSize: size, mouse: CGPoint(x: 2400, y: 35), screen: s, visible: v)
        #expect(o == CGPoint(x: 2250, y: 70 + PanelPlacement.gap))
    }
}
