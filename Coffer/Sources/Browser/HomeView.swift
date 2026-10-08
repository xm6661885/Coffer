import SwiftUI

struct HomeView: View {
    var namespace: Namespace.ID? = nil
    @Namespace private var fallbackNamespace
    @Environment(TransferManager.self) private var transfers
    @Environment(FileProviderRegistry.self) private var registry
    @Environment(RecentsStore.self) private var recents
    @Environment(FavouritesStore.self) private var favourites
    @Environment(AppSettings.self) private var settings
    @Environment(Navigator.self) private var navigator
    @State private var available: Int64?
    @State private var serverSheet: ServerSheet?
    @State private var removing: WebDAVServer?
    var body: some View {
        List {
            Section {
                NavigationLink(value: BrowserRoute(location: .local, path: "/")) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8).fill(Color.pinkSoft).frame(width: 40, height: 40).overlay { Image(systemName: "iphone").foregroundStyle(Color.pinkInk) }
                        VStack(alignment: .leading, spacing: 4) { Text("My iPhone").foregroundStyle(Color.ink); Text(Formatters.bytes(available) + " available").font(.cofferCaption).foregroundStyle(Color.inkSecondary) }
                    }.frame(minHeight: 56)
                }.contextMenu { FavouriteButton(item: .folder(location: .local, path: "/")) }
            }.listRowBackground(Color.surface)
            Section {
                ForEach(registry.servers) { server in
                    NavigationLink(value: BrowserRoute(location: .webdav(server.id), path: server.initialPath)) {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8).fill(Color.surfaceSunken).frame(width: 40, height: 40).overlay { Image(systemName: "server.rack").foregroundStyle(Color.ink) }
                            VStack(alignment: .leading, spacing: 4) { Text(server.name).foregroundStyle(Color.ink); Text(serverDetail(server)).font(.cofferCaption).foregroundStyle(server.lastError == nil || registry.connecting.contains(server.id) ? Color.inkSecondary : Color.danger).contentTransition(.opacity) }
                            Spacer(minLength: 0)
                            if registry.connecting.contains(server.id) { ProgressView().frame(width: 44, height: 44) }
                            else if server.lastError != nil { Button { Task { await registry.reconnect(server.id) } } label: { Image(systemName: "arrow.clockwise").foregroundStyle(Color.pinkInk).frame(width: 44, height: 44).contentShape(.rect) }.buttonStyle(.borderless).accessibilityLabel("Reconnect") }
                        }.frame(minHeight: 56)
                    }.contextMenu {
                        FavouriteButton(item: .folder(location: .webdav(server.id), path: server.initialPath))
                        Button("Reconnect", systemImage: "arrow.clockwise") { Task { await registry.reconnect(server.id) } }.disabled(registry.connecting.contains(server.id))
                        Button("Edit", systemImage: "pencil") { serverSheet = ServerSheet(server: server) }
                        Button("Copy URL", systemImage: "doc.on.doc") { UIPasteboard.general.string = server.baseURL.absoluteString }
                        Button("Disconnect & Remove", systemImage: "trash", role: .destructive) { removing = server }
                    }.swipeActions { Button("Remove", role: .destructive) { removing = server } }
                }.onMove { registry.move(from: $0, to: $1) }
                Button { serverSheet = ServerSheet(server: nil) } label: { Label("Add WebDAV Server", systemImage: "plus.circle").foregroundStyle(Color.pinkInk) }
            } header: { Text("WebDAV") } footer: { if registry.servers.isEmpty { Text("Connect a NAS, a cloud drive or any WebDAV server.") } }
                .listRowBackground(Color.surface)
            if !favourites.items.isEmpty {
                Section("Favourites") {
                    ForEach(favourites.items) { item in
                        Button { navigator.openFavourite(item) } label: { FileRow(item: item, showParent: true) }
                            .buttonStyle(.plain).matchedTransitionSource(id: item.id, in: namespace ?? fallbackNamespace)
                            .contextMenu { FavouriteButton(item: item); Button("Show in Files", systemImage: "folder") { navigator.revealFile(item) } }
                            .swipeActions { Button("Remove", role: .destructive) { favourites.toggle(item) } }
                    }
                }.listRowBackground(Color.surface)
            }
            if settings.showRecents && !recents.entries.isEmpty {
                Section("Recents") {
                    ForEach(recents.entries.prefix(5)) { entry in Button { navigator.open(entry.item, siblings: recents.entries.map(\.item)) } label: { FileRow(item: entry.item, showParent: true) }.buttonStyle(.plain).contextMenu { FavouriteButton(item: entry.item) }.matchedTransitionSource(id: entry.item.id, in: namespace ?? fallbackNamespace) }
                    NavigationLink("Show All") { RecentsView() }
                }.listRowBackground(Color.surface)
            }
        }.listStyle(.insetGrouped).paperList().navigationTitle("Coffer").navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { if transfers.activeCount > 0 { Button { navigator.showTransfers = true } label: { TransferIndicator() }.accessibilityLabel("Transfers") } }
                ToolbarItem(placement: .topBarTrailing) { Menu { Button("Transfers", systemImage: "arrow.up.arrow.down") { navigator.showTransfers = true }; NavigationLink("Settings", destination: SettingsView()); EditButton() } label: { Label("More", systemImage: "ellipsis.circle") } }
            }
            .sheet(item: $serverSheet) { AddServerView(server: $0.server) }
            .confirmationDialog("Remove \"\(removing?.name ?? "")\"?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) { if let server = removing { Button("Disconnect & Remove", role: .destructive) { registry.remove(server.id); removing = nil } }; Button("Cancel", role: .cancel) { removing = nil } } message: { Text("Downloaded files stay on your iPhone.") }
            .task {
                let url = registry.local.rootURL
                available = await Task.detached { (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage }.value
            }
    }
}
private extension HomeView {
    func serverDetail(_ server: WebDAVServer) -> String {
        let base = (server.baseURL.host ?? "") + (server.username.isEmpty ? "" : " · " + server.username)
        if registry.connecting.contains(server.id) { return base + " · Connecting…" }
        return base + (server.lastError == nil ? "" : " · Offline")
    }
}
private struct RecentsView: View {
    @Environment(RecentsStore.self) private var recents
    @Environment(FavouritesStore.self) private var favourites
    @Environment(AppSettings.self) private var settings
    @Environment(Navigator.self) private var navigator
    var body: some View {
        List { ForEach(recents.entries) { entry in Button { navigator.open(entry.item, siblings: recents.entries.map(\.item)) } label: { FileRow(item: entry.item, showParent: true) }.buttonStyle(.plain).contextMenu { FavouriteButton(item: entry.item) }.swipeActions { Button("Remove", role: .destructive) { recents.remove(entry.id) } } } }
            .paperList().navigationTitle("Recents").toolbar { Button("Clear") { recents.clear() } }
    }
}

private struct ServerSheet: Identifiable { let id = UUID(); let server: WebDAVServer? }
