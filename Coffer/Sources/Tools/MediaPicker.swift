import SwiftUI

struct MediaPicker: View {
    enum Kind { case audio, video, text, files }
    let kind: Kind
    var allowedLocations: [LocationID]? = nil
    var actionTitle: String? = nil
    let onChoose: ([FileItem]) -> Void
    @Environment(FileProviderRegistry.self) private var registry
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [String: FileItem] = [:]
    @State private var path: [BrowserRoute] = []
    private var title: String { kind == .audio ? "Add Songs" : kind == .video ? "Add Videos" : kind == .files ? "Choose Files" : "Open" }
    var body: some View {
        NavigationStack(path: $path) {
            List(allowedLocations ?? registry.locations, id: \.self) { location in NavigationLink(value: BrowserRoute(location: location, path: "/")) { Label(registry.displayName(for: location), systemImage: location == .local ? "iphone" : "server.rack") }.listRowBackground(Color.surface) }.paperList().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: BrowserRoute.self) { MediaPickerFolder(route: $0, kind: kind, selected: $selected, cancel: { dismiss() }) { item in onChoose([item]); dismiss() } }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.safeAreaInset(edge: .bottom) { if kind != .text { Button(actionTitle ?? "Add (\(selected.count))") { onChoose(Array(selected.values).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }); dismiss() }.buttonStyle(.glassProminent).tint(.pink).foregroundStyle(Color.onPink).controlSize(.large).disabled(selected.isEmpty).padding(20) } }.presentationBackground(Color.canvas)
    }
}
private struct MediaPickerFolder: View {
    let route: BrowserRoute; let kind: MediaPicker.Kind; @Binding var selected: [String: FileItem]; let cancel: () -> Void; let open: (FileItem) -> Void
    @State private var items: [FileItem] = []; @State private var failure: String?
    @Environment(FileProviderRegistry.self) private var registry
    @Environment(\.dismiss) private var dismiss
    private func allowed(_ item: FileItem) -> Bool { kind == .files ? true : kind == .audio ? item.kind == .audio : kind == .video ? item.kind == .video : item.kind.isTextual }
    private func toggle(_ item: FileItem) { if selected[item.id] == nil { selected[item.id] = item } else { selected[item.id] = nil } }
    var body: some View {
        List(items) { item in
            if item.isDirectory { HStack { NavigationLink(value: BrowserRoute(location: route.location, path: item.path)) { FileRow(item: item) }; if kind == .files { Button { toggle(item) } label: { Image(systemName: selected[item.id] == nil ? "circle" : "checkmark.circle.fill").frame(width: 44, height: 44).foregroundStyle(Color.pinkInk) }.buttonStyle(.plain).accessibilityLabel("Select " + item.name) } }.contextMenu { FavouriteButton(item: item) } }
            else { Button { if kind == .text { open(item) } else if selected[item.id] == nil { selected[item.id] = item } else { selected[item.id] = nil } } label: { HStack { FileRow(item: item); if kind != .text { Image(systemName: selected[item.id] == nil ? "circle" : "checkmark.circle.fill").foregroundStyle(selected[item.id] == nil ? Color.inkTertiary : Color.pinkInk) } } }.buttonStyle(.plain).contextMenu { FavouriteButton(item: item) }.disabled(!allowed(item)).opacity(allowed(item) ? 1 : 0.4) }
        }.paperList().navigationTitle(route.path == "/" ? registry.displayName(for: route.location) : PathUtil.name(route.path)).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) } }.overlay { if let failure { ContentUnavailableView("Couldn't load files", systemImage: "exclamationmark.triangle", description: Text(failure)) } }.task(id: route) { do { items = try await registry.provider(for: route.location).list(route.path).sorted { if $0.isDirectory != $1.isDirectory { return $0.isDirectory }; return $0.name.localizedStandardCompare($1.name) == .orderedAscending }; failure = nil } catch { failure = error.localizedDescription } }
    }
}
