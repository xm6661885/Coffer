import SwiftUI
import QuickLook
import Photos

struct PreviewRouter: View {
    @State private var actions = ViewActions()
    let route: PreviewRoute
    var suppliedURL: URL? = nil
    @Environment(RecentsStore.self) private var recents
    @Environment(FileProviderRegistry.self) private var registry
    @Environment(FileOperations.self) private var operations
    @Environment(Navigator.self) private var navigator
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var url: URL?
    @State private var urlItemID: String?
    @State private var selectedImage: FileItem?
    private var currentItem: FileItem { selectedImage ?? route.item }
    @State private var downloadProgress = -1.0
    @State private var failure: String?
    @State private var immersive = false
    @State private var canQuickLook = false
    @State private var textual = false
    @State private var renaming = false
    @State private var info = false
    @State private var deleting = false
    @State private var sharing = false
    @State private var opening = false
    var body: some View {
        Group {
            Group { if let url { preview(url) } else if let failure { ContentUnavailableView("Couldn't open this file", systemImage: "exclamationmark.triangle", description: Text(failure)) } else if currentItem.location.isRemote { DownloadingView(item: currentItem, progress: downloadProgress) { AppServices.shared.remoteCache.cancel(currentItem); dismiss() } } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) } }
            .background(Color.canvas).navigationTitle(currentItem.name).navigationBarTitleDisplayMode(.inline)
            .navigationSubtitle(Formatters.bytes(currentItem.size) + " · " + Formatters.date(currentItem.modified))
            .toolbar(.hidden, for: .tabBar).toolbarVisibility(immersive ? .hidden : .visible, for: .navigationBar).statusBarHidden(immersive)
            .toolbar { ToolbarItemGroup(placement: .topBarTrailing) {
                Button { sharing = true } label: { Image(systemName: "square.and.arrow.up") }.disabled(url == nil || urlItemID != currentItem.id).accessibilityLabel("Share")
                Menu {
                    Button("Share", systemImage: "square.and.arrow.up") { sharing = true }.disabled(url == nil || urlItemID != currentItem.id)
                    if currentItem.kind == .image || currentItem.kind == .video { Button("Save to Photos", systemImage: "photo.badge.arrow.down") { saveToPhotos() }.disabled(url == nil || urlItemID != currentItem.id) }
                    Button("Open in…", systemImage: "arrow.up.forward.app") { opening = true }.disabled(urlItemID != currentItem.id)
                    Button("Rename", systemImage: "pencil.line") { renaming = true }.disabled(suppliedURL != nil)
                    FavouriteButton(item: currentItem)
                    Button("Get Info", systemImage: "info.circle") { info = true }
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = true }.disabled(suppliedURL != nil)
                    if currentItem.kind.isTextual { Button("Edit", systemImage: "pencil") { navigator.editorItem = currentItem }.disabled(suppliedURL != nil) }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("File options")
            } }
            .sheet(isPresented: $sharing) { if let url { ActivityView(urls: [url]).presentationDetents([.medium, .large]).presentationBackground(Color.canvas) } }
            .sheet(isPresented: $opening) { if let url { NavigationStack { DocumentInteractionView(url: url).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { opening = false } } } }.presentationBackground(Color.canvas) } }
            .sheet(isPresented: $renaming) { RenameSheet(item: currentItem, existing: []) { name in let result = await operations.rename(currentItem, to: name); if result != nil { dismiss() }; return result != nil } }
            .sheet(isPresented: $info) { InfoSheet(item: currentItem, suppliedURL: currentItem.kind == .image && urlItemID == currentItem.id ? url : nil) }
            .confirmationDialog("Delete \"\(currentItem.name)\"?", isPresented: $deleting, titleVisibility: .visible) { Button("Delete", role: .destructive) { actions.submit { await operations.delete([currentItem]); dismiss() } }; Button("Cancel", role: .cancel) { } } message: { Text("This can't be undone.") }
            .task(id: currentItem.id) {
                let openingItem = currentItem
                do {
                    let result: URL
                    if let suppliedURL { result = suppliedURL } else if openingItem.location.isRemote { result = try await AppServices.shared.remoteCache.fetch(openingItem) { downloadProgress = $0 } } else { _ = try await registry.provider(for: openingItem.location).stat(openingItem.path); result = registry.local.url(for: openingItem.path) }
                    let ql = QLPreviewController.canPreview(result as NSURL)
                    let textual = await Task.detached { () -> Bool in
                        let data = try? FileHandle(forReadingFrom: result); defer { try? data?.close() }
                        let prefix = try? data?.read(upToCount: 4096)
                        let text = prefix.flatMap { String(data: $0, encoding: .utf8) }
                        return text != nil && !(text?.contains("\0") ?? true)
                    }.value
                    try Task.checkCancellation(); urlItemID = openingItem.id
                    url = result; canQuickLook = ql; self.textual = textual
                    if suppliedURL == nil { recents.add(openingItem) }
                } catch is CancellationError { } catch { failure = error.localizedDescription; toast.show(error: error) }
            }
        }.managedTasks(actions).onDisappear { navigator.previewSourceID = nil }
    }
    private func saveToPhotos() {
        guard let url, urlItemID == currentItem.id else { return }
        let isVideo = currentItem.kind == .video
        actions.submit {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { toast.show("Allow Coffer to add to Photos in Settings", symbol: "exclamationmark.triangle"); return }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions(); options.originalFilename = url.lastPathComponent
                    request.addResource(with: isVideo ? .video : .photo, fileURL: url, options: options)
                }
                toast.show("Saved to Photos", symbol: "checkmark.circle")
            } catch { toast.show(error: error) }
        }
    }
    @ViewBuilder private func preview(_ url: URL) -> some View {
        switch currentItem.kind {
        case .image: if suppliedURL == nil { ImagePreview(item: currentItem, siblings: route.siblings, immersive: $immersive, onPageChanged: { selectedImage = $0; navigator.previewSourceID = $0.id }) } else { QuickLookPreview(url: url) }
        case .pdf: PDFPreview(item: currentItem, url: url, immersive: $immersive)
        case .markdown: TextPreview(item: currentItem, url: url, mode: .markdown)
        case .html: TextPreview(item: currentItem, url: url, mode: .html)
        case .code: TextPreview(item: currentItem, url: url, mode: .code)
        case .data: TextPreview(item: currentItem, url: url, mode: .data)
        case .text: TextPreview(item: currentItem, url: url, mode: .plain)
        case .font: FontPreview(url: url)
        case .archive: if currentItem.ext == "zip" { ArchivePreview(item: currentItem, url: url) } else { UnsupportedPreview(item: currentItem, url: url) }
        default: if canQuickLook { QuickLookPreview(url: url) } else if textual { TextPreview(item: currentItem, url: url, mode: .plain) } else { UnsupportedPreview(item: currentItem, url: url) }
        }
    }
}
