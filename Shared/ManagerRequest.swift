import AppKit
import os

let requestLog = Logger(subsystem: "com.esilverman.DockFolders", category: "request")

/// Requests a folder app (or its Dock menu plug-in) sends to the DockFolders manager: by distributed
/// notification if the manager is running, else by launching it with `--<request> <folder id>`.
enum ManagerRequest: String, CaseIterable {
    case rebuild // apps were dropped onto the folder: rebuild its icon
    case edit    // "Edit Folder…" in the Dock menu: show the folder in the manager

    var argument: String { "--\(rawValue)" }

    func notificationName(managerBundleID: String) -> Notification.Name {
        .init("\(managerBundleID).\(rawValue)")
    }

    /// The folder id from a launch argument list such as ["DockFolders", "--background", "--rebuild", "<uuid>"].
    func folderID(in arguments: [String]) -> UUID? {
        guard let i = arguments.firstIndex(of: argument), i + 1 < arguments.count else { return nil }
        return UUID(uuidString: arguments[i + 1])
    }

    /// `folderAppBundleID` is the folder app's "<manager id>.folder.<uuid>".
    func send(folderID: UUID, folderAppBundleID: String) {
        guard let managerID = StubInfo.managerBundleID(fromStubID: folderAppBundleID) else {
            return requestLog.error("send \(self.rawValue, privacy: .public): bad folder app id \(folderAppBundleID, privacy: .public)")
        }
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: managerID).isEmpty
        let managerURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: managerID)
        requestLog.notice("""
            send \(self.rawValue, privacy: .public) for \(folderID.uuidString, privacy: .public): \
            manager running=\(running) url=\(managerURL?.path ?? "nil", privacy: .public)
            """)
        if running {
            DistributedNotificationCenter.default().postNotificationName(
                notificationName(managerBundleID: managerID), object: folderID.uuidString, userInfo: nil,
                deliverImmediately: true)
        } else if let manager = managerURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = self == .edit
            config.arguments = (self == .edit ? [] : [StubInfo.backgroundArgument]) + [argument, folderID.uuidString]
            NSWorkspace.shared.openApplication(at: manager, configuration: config)
        }
    }
}
