import SwiftUI

struct DestinationPicker: View {
    @State private var actions = ViewActions()
    var title = "Move Here"
    var allowedLocations: [LocationID]? = nil
    var sources: [FileItem] = []
    var move = false
    var initial: BrowserRoute? = nil
    let onChoose: (LocationID, String) async -> Void
    @Environment(FileProviderRegistry.self) private var registry
    @Environment(FileOperations.self) private var operations
    @Environment(\.dismiss) private var dismiss
    @State private var routes: [BrowserRoute] = []
    var body: some View {
        Group {
            NavigationStack(path: $routes) {
            Group {
                if locations.count == 1, let location = locations.first { folder(BrowserRoute(location: location, path: initial?.location == location ? initial!.path : "/")) }
                else { List(locations, id: \.self) { location in NavigationLink(value: BrowserRoute(location: location, path: "/")) { Label(registry.displayName(for: location), systemImage: location == .local ? "iphone" : "server.rack") }.listRowBackground(Color.surface) }.paperList().navigationTitle("Locations").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } } }
            }.navigationDestination(for: BrowserRoute.self) { folder($0) }
        }.presentationDetents([.large]).presentationBackground(Color.canvas)
        }.managedTasks(actions).fileConflictDialog(inPicker: true).onAppear { operations.conflictPickerCount += 1 }.onDisappear { operations.conflictPickerCount = max(0, operations.conflictPickerCount - 1) }
    }
    private var locations: [LocationID] { allowedLocations ?? registry.locations }
    private func folder(_ route: BrowserRoute) -> some View { DestinationFolder(route: route, title: title, sources: sources, move: move, cancel: { dismiss() }) { location, path in await onChoose(location, path); dismiss() } }
}
private struct DestinationFolder: View {
    @State private var actions = ViewActions()
    let route: BrowserRoute; let title: String; let sources: [FileItem]; let move: Bool
    let cancel: () -> Void; let choose: (LocationID, String) async -> Void
    @Environment(FileProviderRegistry.self) private var registry
    @Environment(FileOperations.self) private var operations
    @Environment(ToastCenter.self) private var toast
    @State private var items: [FileItem] = []
    @State private var newFolder = false
    @State private var busy = false
    private var invalid: Bool { sources.contains { $0.location == route.location && (($0.isDirectory && PathUtil.isAncestor($0.path, of: route.path)) || (move && $0.parentPath == route.path)) } }
    var body: some View {
        Group {
            List(items) { item in
            if item.isDirectory { NavigationLink(value: BrowserRoute(location: route.location, path: item.path)) { FileRow(item: item) }.listRowBackground(Color.canvas).contextMenu { FavouriteButton(item: item) } }
            else { FileRow(item: item).opacity(0.4).listRowBackground(Color.canvas) }
        }.listStyle(.plain).paperList().navigationTitle(route.path == "/" ? registry.displayName(for: route.location) : PathUtil.name(route.path)).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }; ToolbarItem(placement: .topBarTrailing) { Button { newFolder = true } label: { Image(systemName: "folder.badge.plus") }.accessibilityLabel("New Folder") } }
            .safeAreaInset(edge: .bottom) { VStack { if invalid { Text("Choose a different destination folder.").font(.cofferCaption).foregroundStyle(Color.inkSecondary) }; Button { busy = true; actions.submit { await choose(route.location, route.path); busy = false } } label: { Text(title).foregroundStyle(Color.onPink).frame(maxWidth: .infinity) }.buttonStyle(.glassProminent).tint(.pink).controlSize(.large).disabled(invalid || busy) }.padding(20) }
            .task { await reload() }
            .sheet(isPresented: $newFolder) { NewItemSheet(folder: true, existing: Set(items.map(\.name))) { name in let result = await operations.createFolder(named: name, location: route.location, in: route.path); await reload(); return result != nil } }
        }.managedTasks(actions)
    }
    private func reload() async { do { let result = try await registry.provider(for: route.location).list(route.path); withAnimation(.smooth) { items = result.sorted { if $0.isDirectory != $1.isDirectory { return $0.isDirectory }; return $0.name.localizedStandardCompare($1.name) == .orderedAscending } } } catch { toast.show(error: error) } }
}
