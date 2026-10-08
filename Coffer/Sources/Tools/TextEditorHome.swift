import SwiftUI
struct TextEditorHome: View {
    @State private var actions = ViewActions()
    @Environment(FileProviderRegistry.self) private var registry
    @Environment(FileOperations.self) private var operations
    @Environment(RecentsStore.self) private var recents
    @Environment(Navigator.self) private var navigator
    @Environment(ToastCenter.self) private var toast
    @State private var pendingEditor: FileItem?
    @State private var opening = false
    var body: some View {
        Group {
            List {
            Section { Button("New Document", systemImage: "square.and.pencil") { actions.submit { do { let names = Set(try await registry.local.list("/").map(\.name)); let name = PathUtil.uniqueName("Untitled.md", existing: names, isDirectory: false); navigator.newDocument(FileItem(location: .local, path: PathUtil.join("/", name), name: name, isDirectory: false, size: 0, modified: nil, created: nil, etag: nil, contentType: "text/markdown")) } catch { toast.show(error: error) } } }; Button("Open…", systemImage: "folder") { opening = true } }.listRowBackground(Color.surface)
            Section("Recent") { ForEach(recents.entries.filter { $0.item.kind.isTextual }.prefix(20)) { entry in Button { navigator.editorItem = entry.item } label: { FileRow(item: entry.item, showParent: true) }.buttonStyle(.plain).contextMenu { FavouriteButton(item: entry.item) }.swipeActions { Button("Remove", role: .destructive) { recents.remove(entry.id) } } }.listRowBackground(Color.surface) }
        }.paperList().navigationTitle("Markdown Editor").sheet(isPresented: $opening, onDismiss: { if let pendingEditor { navigator.editorItem = pendingEditor; self.pendingEditor = nil } }) { MediaPicker(kind: .text) { pendingEditor = $0.first } }
        }.managedTasks(actions)
    }
}
