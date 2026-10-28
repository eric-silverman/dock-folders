import AppKit
import CoreServices

/// Builds `~/Applications/DockFolders/<Name>.app` from the FolderStub template in our Resources.
enum StubGenerator {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    static let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications/DockFolders")

    static func fileName(for name: String) -> String {
        var s = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        if s.hasPrefix(".") { s = "_" + s.dropFirst() }
        return s
    }

    static func url(for name: String) -> URL {
        directory.appending(path: fileName(for: name) + ".app", directoryHint: .isDirectory)
    }

    /// Stages a full copy next to the destination, then swaps it in, so the Dock never sees a half-built app.
    static func generate(_ folder: Folder, template: URL? = Bundle.main.url(forResource: "FolderStub", withExtension: "app")) throws {
        guard let template else {
            throw Failure(errorDescription: "FolderStub.app is missing from the DockFolders bundle.")
        }
        let fm = FileManager.default
        let dest = url(for: folder.name)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let tmp = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: directory, create: true)
        defer { try? fm.removeItem(at: tmp) }

        let staged = tmp.appending(path: dest.lastPathComponent)
        try fm.copyItem(at: template, to: staged)

        let info = staged.appending(path: "Contents/Info.plist")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: info), format: nil) as? [String: Any] ?? [:]
        let managerID = Bundle.main.bundleIdentifier ?? "com.esilverman.DockFolders"
        try PropertyListSerialization.data(fromPropertyList: StubInfo.rewrite(plist, folder: folder, managerBundleID: managerID),
                                           format: .xml, options: 0).write(to: info)

        let resources = staged.appending(path: "Contents/Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try FolderIcon.icns(appPaths: folder.appPaths).write(to: resources.appending(path: StubInfo.iconName + ".icns"))

        try run("/usr/bin/codesign", "--force", "--deep", "-s", "-", staged.path)

        if fm.fileExists(atPath: dest.path) {
            _ = try fm.replaceItemAt(dest, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: dest)
        }
        try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: dest.path) // nudge Finder/Dock icon caches
        LSRegisterURL(dest as CFURL, true)
    }

    private static func run(_ tool: String, _ args: String...) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw Failure(errorDescription: "\(tool) failed: \(msg)")
        }
    }
}

/// Composite folder icon: up to 9 app icons in a 3×3 grid on a rounded-rect background.
enum FolderIcon {
    // (OSType, pixel size) for every standard slot, 16pt…512pt@2x.
    static let slots: [(String, Int)] = [
        ("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64), ("ic07", 128),
        ("ic13", 256), ("ic08", 256), ("ic14", 512), ("ic09", 512), ("ic10", 1024),
    ]

    static func icns(appPaths: [String]) -> Data {
        let icons = appPaths.filter { FileManager.default.fileExists(atPath: $0) }.prefix(9)
            .map(appIcon(forPath:))
        var pngs: [Int: Data] = [:]
        var body = Data()
        for (type, px) in slots {
            let png = pngs[px] ?? render(icons, pixels: px)
            pngs[px] = png
            body.append(Data(type.utf8))
            body.append(bigEndian(png.count + 8))
            body.append(png)
        }
        return Data("icns".utf8) + bigEndian(body.count + 8) + body
    }

    private static func bigEndian(_ n: Int) -> Data {
        withUnsafeBytes(of: UInt32(n).bigEndian) { Data($0) }
    }

    private static func render(_ icons: [NSImage], pixels px: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high

        let s = CGFloat(px)
        let body = NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.1, dy: s * 0.1) // macOS icon grid margin
        let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
        NSGradient(starting: NSColor(white: 0.42, alpha: 1), ending: NSColor(white: 0.22, alpha: 1))!.draw(in: shape, angle: -90)

        let inner = body.insetBy(dx: body.width * 0.08, dy: body.width * 0.08)
        let cell = inner.width / 3
        let rows = (icons.count + 2) / 3
        let top = inner.maxY - CGFloat(3 - rows) * cell / 2 // center the used rows vertically
        for (i, icon) in icons.enumerated() {
            let row = i / 3, col = i % 3
            let inRow = min(3, icons.count - row * 3)
            let left = inner.minX + CGFloat(3 - inRow) * cell / 2 // center a short row
            let r = NSRect(x: left + CGFloat(col) * cell, y: top - CGFloat(row + 1) * cell, width: cell, height: cell)
            icon.draw(in: r.insetBy(dx: cell * 0.04, dy: cell * 0.04))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
}
