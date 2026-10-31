// Renders the DockFolders app icon: a folder tile holding a 2×2 grid of apps.
//   swift scripts/make-icon.swift <out.png> [pixels]
import AppKit

let out = CommandLine.arguments[1]
let px = Int(CommandLine.arguments.dropFirst(2).first ?? "1024")!
let s = CGFloat(px) / 1024 // design in 1024 units

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * s, y: y * s, width: w * s, height: h * s) }
func rounded(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: radius * s, yRadius: radius * s) }
func shadow(_ blur: CGFloat, _ dy: CGFloat, _ alpha: CGFloat) {
    let sh = NSShadow(); sh.shadowBlurRadius = blur * s; sh.shadowOffset = NSSize(width: 0, height: -dy * s)
    sh.shadowColor = .black.withAlphaComponent(alpha); sh.set()
}

// The macOS icon grid's 824pt rounded square: a white folder tile holding a 2×2 grid of apps.
let body = rect(100, 100, 824, 824)
NSGraphicsContext.saveGraphicsState()
shadow(28, 12, 0.3)
rgb(1, 1, 1).setFill()
rounded(body, 185).fill() // casts the shadow; the gradient can't
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: rgb(1, 1, 1), ending: rgb(0.92, 0.93, 0.97))!.draw(in: rounded(body, 185), angle: -90)

let colors = [rgb(1.0, 0.62, 0.20), rgb(0.98, 0.33, 0.52), rgb(0.22, 0.78, 0.45), rgb(0.20, 0.62, 1.0)]
let cell: CGFloat = 280, gap: CGFloat = 80, inset = (824 - 2 * cell - gap) / 2
for (i, c) in colors.enumerated() {
    let r = rect(100 + inset + CGFloat(i % 2) * (cell + gap), 100 + inset + CGFloat(1 - i / 2) * (cell + gap), cell, cell)
    let top = c.blended(withFraction: 0.2, of: .white)!, bottom = c.blended(withFraction: 0.12, of: .black)!
    NSGradient(starting: top, ending: bottom)!.draw(in: rounded(r, 68), angle: -90)
}

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
