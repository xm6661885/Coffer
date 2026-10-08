import SwiftUI
import PhotosUI

private struct MediaUploadModifier: ViewModifier {
    let kind: UploadFileKind
    let destination: BrowserRoute?
    let enabled: Bool
    @State private var presented = false
    func body(content: Content) -> some View {
        content.toolbar {
            if enabled { ToolbarItem(placement: .topBarTrailing) {
                Button { presented = true } label: { Label("Upload", systemImage: "arrow.up.doc") }
            } }
        }.sheet(isPresented: $presented) { UploadSheet(kind: kind, fixedDestination: destination) }
    }
}
extension View {
    func mediaUpload(kind: UploadFileKind, destination: BrowserRoute? = nil, enabled: Bool = true) -> some View {
        modifier(MediaUploadModifier(kind: kind, destination: destination, enabled: enabled))
    }
}
private struct UploadSheet: View {
    let kind: UploadFileKind
    let fixedDestination: BrowserRoute?
    @State private var actions = ViewActions()
    @State private var destination = BrowserRoute(location: .local, path: "/")
    @State private var filesPresented = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var busy = false
    @State private var failure: String?
    @Environment(AppSettings.self) private var settings
    @Environment(FileProviderRegistry.self) private var registry
    @Environment(TransferManager.self) private var transfers
    @Environment(ImportService.self) private var importer
    @Environment(\.dismiss) private var dismiss
    private var target: BrowserRoute { fixedDestination ?? destination }
    private var sources: [BrowserRoute] {
        let configured = switch kind { case .music: settings.musicSources; case .videos: settings.videoSources; case .pictures: settings.pictureSources; case .files: [BrowserRoute]() }
        var result = [BrowserRoute(location: .local, path: "/")]
        for source in configured where !result.contains(source) { result.append(source) }
        return result
    }
    private var photoFilter: PHPickerFilter { switch kind { case .videos: .videos; case .pictures: .images; default: .any(of: [.images, .videos]) } }
    private func title(_ route: BrowserRoute) -> String {
        registry.displayName(for: route.location) + (route.path == "/" ? "" : " › " + route.path)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Upload to") {
                    if let fixedDestination { Text(title(fixedDestination)).foregroundStyle(Color.ink) }
                    else { Picker("Location", selection: $destination) { ForEach(sources, id: \.self) { Text(title($0)).tag($0) } } }
                }.listRowBackground(Color.surface)
                Section {
                    Button { filesPresented = true } label: { Label("Choose from Files", systemImage: "doc") }
                    if kind != .music {
                        PhotosPicker(selection: $photos, matching: photoFilter, preferredItemEncoding: .current) {
                            Label("Choose from Photos", systemImage: "photo.on.rectangle")
                        }
                    }
                } footer: { if kind != .files { Text(kind.requirement) } }
                    .listRowBackground(Color.surface)
                if busy { Section { ProgressView(target.location.isRemote ? "Preparing upload…" : "Saving…") }.listRowBackground(Color.clear) }
            }.paperList().navigationTitle("Upload").navigationBarTitleDisplayMode(.inline)
                .disabled(busy)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
        }.presentationDetents([.medium, .large]).presentationBackground(Color.canvas).interactiveDismissDisabled(busy)
            .fileImporter(isPresented: $filesPresented, allowedContentTypes: kind.allowedContentTypes, allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): let target = target; busy = true; actions.submit { await upload(urls, to: target) }
                case .failure(let error): failure = error.localizedDescription
                }
            }
            .onChange(of: photos) { _, selected in
                guard !selected.isEmpty && !busy else { return }
                let target = target; busy = true
                actions.submit {
                    var urls: [URL] = []
                    do {
                        for photo in selected {
                            try Task.checkCancellation()
                            guard let file = try await photo.loadTransferable(type: FileTransferable.self) else { throw FileProviderError.other("Couldn't load the selected photo or video.") }
                            urls.append(file.url)
                        }
                        await upload(urls, to: target, dismissWhenDone: false)
                    } catch { failure = error.localizedDescription }
                    await Task.detached { for url in urls { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) } }.value
                    photos = []; busy = false
                    if failure == nil { dismiss() }
                }
            }
            .alert("Couldn't upload", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) { Button("OK") { failure = nil } } message: { Text(failure ?? "") }
            .managedTasks(actions)
    }
    private func upload(_ urls: [URL], to target: BrowserRoute, dismissWhenDone: Bool = true) async {
        do {
            try await kind.validate(urls)
            try Task.checkCancellation()
            if target.location.isRemote {
                let accepted = await transfers.enqueueExternalUploads(urls, to: target.location, dirPath: target.path)
                guard accepted == urls.count else { throw FileProviderError.other("Some files couldn't be queued for upload. Successfully queued files remain in Transfers.") }
            }
            else {
                let imported = await importer.importFiles(urls, to: target.path, move: false)
                guard imported.count == urls.count else { throw FileProviderError.other("Some files couldn't be saved. Successfully saved files remain in the destination.") }
            }
            if dismissWhenDone { busy = false; dismiss() }
        } catch { failure = error.localizedDescription; if dismissWhenDone { busy = false } }
    }
}
