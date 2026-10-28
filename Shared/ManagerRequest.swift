import AppKit
import os

/// One log subsystem for the manager, folder apps and the Dock plug-in (one product), so a single
/// `log show --predicate 'subsystem == "com.esilverman.DockFolders"'` follows a request end to end.
let requestLog = Logger(subsystem: "com.esilverman.DockFolders", category: "request")

/// Requests a folder app (or its Dock menu plug-in) sends to the DockFolders manager, the only writer of
/// folders.json: by distributed notification if the manager is running, else by launching it with
/// `--<request> <folder id> [app paths…]`.
enum ManagerRequest: String, CaseIterable {
    case add  // apps were dropped onto the folder: add them, rebuild its icon, refresh the Dock
    case edit // "Edit Folder…" in the Dock menu: show the folder in the manager

    static let pathsKey = "paths"

    var argument: String { "--\(rawValue)" }

    func notificationName(managerBundleID: String) -> Notification.Name {
        .init("\(managerBundleID).\(rawValue)")
    }

    /// Folder id and app paths from launch arguments such as [..., "--add", "<uuid>", "/Applications/X.app"].
    func parse(_ arguments: [String]) -> (id: UUID, paths: [String])? {
        guard let i = arguments.firstIndex(of: argument), i + 1 < arguments.count,
              let id = UUID(uuidString: arguments[i + 1]) else { return nil }
        return (id, Array(arguments[(i + 2)...].prefix { !$0.hasPrefix("--") }))
    }

    /// `folderAppBundleID` is the folder app's "<manager id>.folder.<uuid>".
    func send(folderID: UUID, paths: [String] = [], folderAppBundleID: String) {
        guard let managerID = StubInfo.managerBundleID(fromStubID: folderAppBundleID) else {
            return requestLog.error("send \(self.rawValue, privacy: .public): bad folder app id \(folderAppBundleID, privacy: .public)")
        }
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: managerID).isEmpty
        let managerURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: managerID)
        requestLog.notice("""
            send \(self.rawValue, privacy: .public) for \(folderID.uuidString, privacy: .public) \
            (\(paths.count) paths): manager running=\(running) url=\(managerURL?.path ?? "nil", privacy: .public)
            """)
        if running {
            // No userInfo for .edit: the Dock plug-in runs sandboxed, where distributed userInfo isn't allowed.
            DistributedNotificationCenter.default().postNotificationName(
                notificationName(managerBundleID: managerID), object: folderID.uuidString,
                userInfo: paths.isEmpty ? nil : [Self.pathsKey: paths], deliverImmediately: true)
        } else if let manager = managerURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = self == .edit
            config.arguments = (self == .edit ? [] : [StubInfo.backgroundArgument]) + [argument, folderID.uuidString] + paths
            NSWorkspace.shared.openApplication(at: manager, configuration: config)
        }
    }
}
