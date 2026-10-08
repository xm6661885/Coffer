import SwiftUI
import UniformTypeIdentifiers

struct InfoSheet: View {
    let item: FileItem
    var suppliedURL: URL? = nil
    @Environment(FileProviderRegistry.self) private var registry
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var resolved: FileItem?
    @State private var mediaFields: [(String, String)] = []
    private var currentItem: FileItem { resolved ?? item }
    @State private var imageMetadata: ImageMetadata?
    @State private var loadingImageMetadata = false
    @State private var metadataError: String?
    @State private var retry = 0
    @State private var folderSize: Int64?
    var body: some View {
        NavigationStack {
            Form {
                Section { VStack(spacing: 16) { FileIconView(item: currentItem, size: 96); Text(currentItem.name).font(.cofferTitle).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).padding(.vertical, 16) }.listRowBackground(Color.canvas)
                Section {
                    LabeledContent("Kind", value: currentItem.isDirectory ? "Folder" : (UTType(filenameExtension: currentItem.ext)?.localizedDescription ?? "\(currentItem.ext.uppercased()) File"))
                    LabeledContent("Size", value: sizeText)
                    LabeledContent("Where", value: registry.displayName(for: currentItem.location) + (currentItem.parentPath == "/" ? "" : " › " + PathUtil.components(currentItem.parentPath).joined(separator: " › ")))
                    if let date = currentItem.created { LabeledContent("Created", value: date.formatted(date: .long, time: .standard)) }
                    if let date = currentItem.modified { LabeledContent("Modified", value: date.formatted(date: .long, time: .standard)) }
                    if let provider = try? registry.provider(for: currentItem.location) as? WebDAVFileProvider { LabeledContent("URL", value: provider.client.url(for: currentItem.path, isDirectory: currentItem.isDirectory).absoluteString).textSelection(.enabled) }
                    if let etag = currentItem.etag { LabeledContent("ETag", value: etag).textSelection(.enabled) }
                }.listRowBackground(Color.surface)
                if !mediaFields.isEmpty { Section { ForEach(Array(mediaFields.enumerated()), id: \.offset) { _, field in LabeledContent(field.0, value: field.1) } }.listRowBackground(Color.surface) }
                if currentItem.kind == .image {
                    if loadingImageMetadata { Section { ProgressView("Loading image details…") }.listRowBackground(Color.clear) }
                    if let imageMetadata {
                        metadataSection("Image", imageMetadata.imageFields)
                        metadataSection("EXIF", imageMetadata.exifFields)
                        metadataSection("GPS", imageMetadata.gpsFields)
                        ForEach(imageMetadata.additional) { section in
                            Section {
                                DisclosureGroup(section.title) { ForEach(section.fields) { field in LabeledContent(field.name, value: field.value).textSelection(.enabled) } }
                            }.listRowBackground(Color.surface)
                        }
                        if !imageMetadata.hasExif { Section { Text("This image has no EXIF metadata.").foregroundStyle(Color.inkSecondary) }.listRowBackground(Color.clear) }
                    }
                    if let metadataError { Section { Text(metadataError).foregroundStyle(Color.inkSecondary); Button("Try Again") { retry += 1 } }.listRowBackground(Color.surface) }
                }
                Section { Button("Copy Path") { UIPasteboard.general.string = currentItem.path; toast.show("Copied", symbol: "checkmark") } }.listRowBackground(Color.surface)
            }.paperList().navigationTitle("Info").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task(id: "\(item.id):\(retry)") {
                    loadingImageMetadata = item.kind == .image; metadataError = nil; imageMetadata = nil; mediaFields = []; resolved = nil; folderSize = nil
                    defer { loadingImageMetadata = false }
                    resolved = try? await registry.provider(for: item.location).stat(item.path)
                    if currentItem.kind == .image {
                        do {
                            let url: URL
                            if let suppliedURL, FileManager.default.fileExists(atPath: suppliedURL.path) { url = suppliedURL }
                            else if currentItem.location == .local { url = registry.local.url(for: currentItem.path) }
                            else { url = try await AppServices.shared.remoteCache.fetch(currentItem, progress: { _ in }) }
                            let metadata = try await Task.detached { try ImageMetadata.read(url) }.value
                            try Task.checkCancellation(); imageMetadata = metadata
                        } catch is CancellationError { } catch { metadataError = error.localizedDescription }
                    } else if currentItem.kind.isMedia {
                        let url: URL? = currentItem.location == .local ? registry.local.url(for: currentItem.path) : (AppServices.shared.remoteCache.isCached(currentItem) ? AppServices.shared.remoteCache.localURL(for: currentItem) : nil)
                        if let url { mediaFields = await MediaInfo.fields(for: currentItem, url: url) }
                    }
                    guard currentItem.isDirectory && currentItem.location == .local else { return }
                    let url = registry.local.url(for: currentItem.path)
                    folderSize = await Task.detached { Self.calculateSize(url) }.value
                }
        }.presentationDetents([.medium, .large]).presentationBackground(Color.canvas)
    }
    @ViewBuilder private func metadataSection(_ title: String, _ fields: [ImageMetadataField]) -> some View {
        if !fields.isEmpty { Section(title) { ForEach(fields) { field in LabeledContent(field.name, value: field.value).textSelection(.enabled) } }.listRowBackground(Color.surface) }
    }
    nonisolated private static func calculateSize(_ url: URL) -> Int64 {
        var size: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) {
            for case let u as URL in enumerator { let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]); if v?.isDirectory != true { size += Int64(v?.fileSize ?? 0) } }
        }
        return size
    }
    private var sizeText: String { let size = currentItem.isDirectory ? folderSize : currentItem.size; if currentItem.isDirectory && currentItem.location == .local && size == nil { return "Calculating…" }; return size.map { "\(Formatters.bytes($0)) (\($0.formatted()) bytes)" } ?? "—" }
}
