import SwiftUI
import UniformTypeIdentifiers

@main
struct DockFoldersApp: App {
    @State private var model = FolderModel()

    var body: some Scene {
        Window("DockFolders", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 640, minHeight: 420)
        }
        MenuBarExtra("DockFolders", systemImage: "square.grid.3x3.square") {
            MenuContent().environment(model)
        }
    }
}

private struct MenuContent: View {
    @Environment(FolderModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open DockFolders…") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Button("Refresh Dock") { model.refreshDock() }
        Divider()
        Button("Quit DockFolders") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

struct ContentView: View {
    @Environment(FolderModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                ForEach(model.folders) { folder in
                    Label(folder.name, systemImage: "folder").tag(folder.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .toolbar {
                Button("New Folder", systemImage: "plus") { model.addFolder() }
            }
        } detail: {
            if let id = model.selection, let folder = model.folder(id) {
                FolderDetail(folder: folder).id(id)
            } else {
                ContentUnavailableView("No Folder", systemImage: "folder.badge.plus",
                                       description: Text("Click + to create a folder."))
            }
        }
        .toolbar {
            if model.dockNeedsRefresh {
                Button("Refresh Dock", systemImage: "arrow.clockwise") { model.refreshDock() }
                    .help("The Dock caches folder icons and names. Restart it to show the changes.")
            }
        }
        .alert("DockFolders", isPresented: Binding(get: { model.errorMessage != nil },
                                                   set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onAppear { NSApp.activate() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reloadDockState()
        }
    }
}

private struct FolderDetail: View {
    @Environment(FolderModel.self) private var model
    let folder: Folder
    @State private var name = ""
    @State private var confirmAdd = false
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Folder name", text: $name)
                .font(.title2)
                .textFieldStyle(.plain)
                .onSubmit(commitName)

            List {
                ForEach(folder.appPaths, id: \.self) { path in
                    AppRow(path: path) { model.removeApp(path, from: folder.id) }
                }
                .onMove { model.moveApps(in: folder.id, from: $0, to: $1) }
            }
            .dropDestination(for: URL.self) { urls, _ in
                model.addApps(urls, to: folder.id)
                return true
            }
            .overlay {
                if folder.appPaths.isEmpty {
                    ContentUnavailableView("Drag Apps Here", systemImage: "square.grid.3x3",
                                           description: Text("Drop apps from Finder, or click Add Apps."))
                }
            }

            HStack {
                Button("Add Apps…", action: pickApps)
                Spacer()
                Button("Delete Folder", role: .destructive) { confirmDelete = true }
                Button("Show in Finder") { model.showInFinder(folder.id) }
                if model.isInDock(folder) {
                    Label("In Dock", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                } else {
                    Button("Add to Dock") { confirmAdd = true }.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .onAppear { name = folder.name }
        .onDisappear(perform: commitName)
        .confirmationDialog("Add “\(folder.name)” to the Dock?", isPresented: $confirmAdd) {
            Button("Add and Restart Dock") { commitName(); model.addToDock(folder.id) }
            Button("Show in Finder Instead") { model.showInFinder(folder.id) }
        } message: {
            Text("The Dock restarts for a moment. Or drag the app from Finder into the Dock yourself.")
        }
        .confirmationDialog("Delete “\(folder.name)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { model.delete(folder.id) }
        } message: {
            Text("The folder app moves to the Trash\(model.isInDock(folder) ? " and the Dock restarts to remove it" : ""). The apps inside aren't touched.")
        }
    }

    private func commitName() {
        model.rename(folder.id, to: name)
        name = model.folder(folder.id)?.name ?? name // revert if the rename was rejected
    }

    private func pickApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        if panel.runModal() == .OK { model.addApps(panel.urls, to: folder.id) }
    }
}

private struct AppRow: View {
    let path: String
    let remove: () -> Void

    var body: some View {
        let exists = FileManager.default.fileExists(atPath: path)
        HStack {
            Image(nsImage: appIcon(forPath: path))
                .resizable()
                .frame(width: 24, height: 24)
            Text(exists ? FileManager.default.displayName(atPath: path)
                        : URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
            if !exists { Text("Missing").foregroundStyle(.secondary) }
            Spacer()
            Button("Remove", systemImage: "minus.circle", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .opacity(exists ? 1 : 0.5)
        .help(path)
    }
}
