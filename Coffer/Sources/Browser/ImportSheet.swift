import SwiftUI

struct ImportSheet: View {
    @State private var actions = ViewActions()
    let urls: [URL]
    @Environment(ImportService.self) private var importer
    @Environment(AppSettings.self) private var settings
    @State private var destination = "/"
    @State private var choosing = false
    @State private var saving = false
    @State private var fileItems: [URL: FileItem] = [:]
    var body: some View {
        Group {
            NavigationStack {
            List {
                Section { ForEach(Array(urls.prefix(5).enumerated()), id: \.offset) { _, url in HStack(spacing: 12) { if let item = fileItems[url] { FileIconView(item: item); VStack(alignment: .leading, spacing: 4) { Text(item.name).foregroundStyle(Color.ink); Text(Formatters.bytes(item.size)).font(.cofferCaption).foregroundStyle(Color.inkSecondary) } } else { Label(url.lastPathComponent, systemImage: FileKind(ext: url.pathExtension.lowercased()).symbol) } } }; if urls.count > 5 { Text("and \(urls.count - 5) more").foregroundStyle(Color.inkSecondary) } }.listRowBackground(Color.surface)
                Section { Button { choosing = true } label: { LabeledContent("Destination", value: destination == "/" ? "My iPhone" : destination) } }.listRowBackground(Color.surface)
            }.paperList().navigationTitle("Save to Coffer").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { importer.cancelPending() }.disabled(saving) }; ToolbarItem(placement: .confirmationAction) { Button { saving = true; actions.submit { _ = await importer.importFiles(urls, to: destination, move: false); settings.lastImportDestination = destination; importer.pending?.urls.removeAll { importer.lastImportedURLs.contains($0) }; if importer.pending?.urls.isEmpty == true { importer.pending = nil } else { saving = false } } } label: { Text("Save").foregroundStyle(Color.onPink) }.buttonStyle(.glassProminent).tint(.pink).disabled(saving) } }
                .task { destination = settings.lastImportDestination; if (try? await AppServices.shared.registry.local.stat(destination)) == nil { destination = "/" }; for url in urls { let info = await Task.detached { () -> FileItem? in let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }; guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else { return nil }; return FileItem(location: .local, path: "/" + url.lastPathComponent, name: url.lastPathComponent, isDirectory: values.isDirectory == true, size: values.fileSize.map(Int64.init), modified: nil, created: nil, etag: nil, contentType: nil) }.value; if let info { fileItems[url] = info } } }
                .sheet(isPresented: $choosing) { DestinationPicker(title: "Save Here", allowedLocations: [.local], initial: BrowserRoute(location: .local, path: destination)) { _, path in destination = path } }
        }.presentationDetents([.medium]).presentationBackground(Color.canvas).interactiveDismissDisabled(saving)
        }.managedTasks(actions)
    }
}
