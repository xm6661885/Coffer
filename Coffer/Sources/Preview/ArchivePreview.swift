import SwiftUI
import ZIPFoundation

struct ArchivePreview: View {
    @State private var actions = ViewActions()
    let item: FileItem
    let url: URL
    var prefix = ""
    @Environment(ToastCenter.self) private var toast
    @Environment(Navigator.self) private var navigator
    @State private var entries: [ArchiveRow] = []
    @State private var totalSize: Int64 = 0
    @State private var count = 0
    @State private var progress: Double?
    @State private var extracted: ArchiveFile?
    var body: some View {
        Group {
            List(entries) { entry in
            if entry.directory { NavigationLink { ArchivePreview(item: item, url: url, prefix: entry.path + "/").navigationTitle(entry.name) } label: { Label(entry.name, systemImage: "folder.fill").foregroundStyle(Color.pinkInk) } }
            else { Button { actions.submit { await open(entry) } } label: { HStack { Label(entry.name, systemImage: FileKind(ext: PathUtil.ext(entry.name)).symbol); Spacer(); Text(Formatters.bytes(entry.size)).font(.cofferCaption).foregroundStyle(Color.inkSecondary) } }.foregroundStyle(Color.ink) }
        }.paperList()
            .safeAreaInset(edge: .top) { Text("\(count) items · \(Formatters.bytes(totalSize)) uncompressed").font(.cofferCaption).foregroundStyle(Color.inkSecondary).padding(12) }
            .safeAreaInset(edge: .bottom) { VStack { if let progress { ProgressBar(value: progress) }; Button { actions.submit { await uncompress() } } label: { Text("Uncompress").foregroundStyle(Color.onPink).frame(maxWidth: .infinity) }.buttonStyle(.glassProminent).tint(.pink).controlSize(.large).disabled(progress != nil) }.padding(20) }
            .task(id: prefix) {
                do {
                    let result = try await Task.detached { () -> ([ArchiveRow], Int, Int64) in
                        var archive = try Archive(url: url, accessMode: .read)
                        if archive.contains(where: { $0.path.contains("\u{FFFD}") }), let gb = TextDecoding.encodings.first(where: { $0.0 == "GB18030" })?.1 { archive = try Archive(url: url, accessMode: .read, pathEncoding: gb) }
                        var rows: [String: ArchiveRow] = [:]; var size: Int64 = 0; var count = 0
                        for entry in archive {
                            size += Int64(entry.uncompressedSize); count += 1
                            guard entry.path.hasPrefix(prefix) else { continue }
                            let remainder = String(entry.path.dropFirst(prefix.count)), components = remainder.split(separator: "/")
                            guard let name = components.first else { continue }
                            let directory = components.count > 1 || entry.type == .directory
                            rows[String(name)] = ArchiveRow(path: prefix + String(name), name: String(name), directory: directory, size: directory ? nil : Int64(entry.uncompressedSize))
                        }
                        return (rows.values.sorted { if $0.directory != $1.directory { return $0.directory }; return $0.name.localizedStandardCompare($1.name) == .orderedAscending }, count, size)
                    }.value
                    entries = result.0; count = result.1; totalSize = result.2
                } catch { toast.show(error: error) }
            }
            .navigationDestination(item: $extracted) { file in PreviewRouter(route: PreviewRoute(item: file.item, siblings: [file.item]), suppliedURL: file.url) }
        }.managedTasks(actions)
    }
    private func open(_ row: ArchiveRow) async {
        do {
            let target = try await Task.detached { () -> URL in
                let archive = try ZipService.archive(url)
                guard let entry = archive[row.path], entry.type == .file else { throw FileProviderError.notFound(row.name) }
                let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let target = dir.appending(path: row.name); _ = try archive.extract(entry, to: target); return target
            }.value
            let preview = FileItem(location: .local, path: PathUtil.join("/", row.name), name: row.name, isDirectory: false, size: row.size, modified: nil, created: nil, etag: nil, contentType: nil)
            extracted = ArchiveFile(url: target, item: preview)
        } catch { toast.show(error: error) }
    }
    private func uncompress() async {
        progress = 0; defer { progress = nil }
        do {
            let local = AppServices.shared.registry.local
            let dir = item.location == .local ? local.url(for: item.parentPath) : local.rootURL
            let folder = try await ZipService.uncompress(url, into: dir) { value in DispatchQueue.main.async { progress = value } }
            let path = PathUtil.join(item.location == .local ? item.parentPath : "/", folder.lastPathComponent)
            AppServices.shared.operations.changed(.local, PathUtil.parent(path)); toast.show("Uncompressed to \"\(folder.lastPathComponent)\"", symbol: "checkmark", actionTitle: "Show") { navigator.reveal(location: .local, path: path) }
        } catch { toast.show(error: error) }
    }
}
private struct ArchiveRow: Identifiable { let path: String; let name: String; let directory: Bool; let size: Int64?; var id: String { path } }
private struct ArchiveFile: Hashable { let url: URL; let item: FileItem }
