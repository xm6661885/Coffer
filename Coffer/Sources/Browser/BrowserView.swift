import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct BrowserView: View {
    @State private var actions = ViewActions()
    let route: BrowserRoute
    @State private var model: BrowserModel
    @State private var editMode = EditMode.inactive
    @State private var searchPresented = false
    @State private var sheet: BrowserSheet?
    @State private var deleting: [FileItem] = []
    @State private var moreItem: FileItem?
    @State private var pendingEditor: FileItem?
    @State private var importing = false
    @State private var choosingUpload = false
    @State private var compressionID: UUID?
    @State private var photos: [PhotosPickerItem] = []
    @State private var share: ShareRequest?
    @State private var selectionTrigger = 0
    @State private var deleteTrigger = 0
    @Environment(FileOperations.self) private var operations
    @Environment(Clipboard.self) private var clipboard
    @Environment(TransferManager.self) private var transfers
    @Environment(ImportService.self) private var importer
    @Environment(ToastCenter.self) private var toast
    @State private var watcher = DirectoryWatcher()
    @Environment(AppSettings.self) private var settings
    @Environment(Navigator.self) private var navigator
    @Environment(\.scenePhase) private var phase
    @Namespace private var fallbackNamespace
    let sourceNamespace: Namespace.ID?
    private var previewNamespace: Namespace.ID { sourceNamespace ?? fallbackNamespace }
    init(route: BrowserRoute, namespace: Namespace.ID? = nil) { self.route = route; self.sourceNamespace = namespace; _model = State(initialValue: BrowserModel(route: route)) }
    var body: some View {
        @Bindable var model = model
        @Bindable var settings = settings
        Group {
            GeometryReader { geometry in
                if settings.viewMode == .list {
                    List(selection: $model.selection) {
                        if model.visibleItems.isEmpty {
                            emptyState.frame(maxWidth: .infinity, minHeight: geometry.size.height)
                                .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.canvas)
                        }
                        ForEach(model.visibleItems) { item in
                            Button { tap(item) } label: { FileRow(item: item, showParent: model.scope == .all) }
                                .buttonStyle(.plain).tag(item.id).matchedTransitionSource(id: item.id, in: previewNamespace)
                                .listRowBackground(navigator.highlightID == item.id ? Color.pinkSoft : Color.canvas).listRowSeparatorTint(.hairline)
                                .contextMenu { if !editMode.isEditing { FileContextMenu(item: item, cached: AppServices.shared.remoteCache.pinned.contains(item.id)) { perform($0, items: [item]) } } }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("Delete", role: .destructive) { deleting = [item] }
                                    Button { moreItem = item } label: { Label("More", systemImage: "ellipsis") }.tint(.inkSecondary)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if item.kind == .audio { Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { perform(.playNext, items: [item]) }.tint(.pinkInk) }
                                    Button("Copy", systemImage: "doc.on.doc") { perform(.copy, items: [item]) }.tint(.inkSecondary)
                                }
                                .onDrag { item.location == .local ? (NSItemProvider(contentsOf: model.registry.local.url(for: item.path)) ?? NSItemProvider()) : NSItemProvider() }
                            .dropDestination(for: URL.self) { urls, _ in guard item.isDirectory else { return false }; importDropped(urls, to: item.path); return true }
                    }
                }.listStyle(.plain).paperList()
                    .contentMargins(.vertical, 0, for: .scrollContent)
                    .scrollBounceBehavior(.always)
            } else {
                ScrollView {
                    if model.visibleItems.isEmpty {
                        emptyState.frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    } else { LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 16)], spacing: 20) {
                    ForEach(model.visibleItems) { item in Button { tap(item) } label: { FileGridCell(item: item, selecting: editMode.isEditing, selected: model.selection.contains(item.id)) }.buttonStyle(.plain).matchedTransitionSource(id: item.id, in: previewNamespace).contextMenu { if !editMode.isEditing { FileContextMenu(item: item, cached: AppServices.shared.remoteCache.pinned.contains(item.id)) { perform($0, items: [item]) } } }.onDrag { item.location == .local ? (NSItemProvider(contentsOf: model.registry.local.url(for: item.path)) ?? NSItemProvider()) : NSItemProvider() }.dropDestination(for: URL.self) { urls, _ in guard item.isDirectory && !urls.isEmpty else { return false }; importDropped(urls, to: item.path); return true } }
                }.padding(20) }
                }.background(Color.canvas).scrollBounceBehavior(.always)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in guard !urls.isEmpty else { return false }; importDropped(urls, to: route.path); return true }
        .navigationTitle(editMode.isEditing ? (model.selection.isEmpty ? "Select Items" : "\(model.selection.count) Selected") : model.title)
        .navigationBarBackButtonHidden(editMode.isEditing)
        .environment(\.editMode, $editMode)
        .toolbar(editMode.isEditing ? .hidden : .visible, for: .tabBar).navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(model.error != nil && !model.items.isEmpty && route.location.isRemote ? "Offline · Showing saved list" : model.isLoading && !model.items.isEmpty ? "Updating…" : "")
        .searchable(text: $model.query, isPresented: $searchPresented, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search in \(model.title)")
        .searchScopes($model.scope) {
            Text("This Folder").tag(SearchScope.folder)
            if route.location == .local { Text("Everywhere").tag(SearchScope.all) }
        }
        .toolbarTitleMenu { ForEach(ancestors, id: \.self) { path in Button { navigator.reveal(location: route.location, path: path) } label: { Label(path == "/" ? model.registry.displayName(for: route.location) : PathUtil.name(path), systemImage: "folder") } } }
        .toolbar {
            if editMode.isEditing {
                ToolbarItem(placement: .topBarLeading) { Button(model.selection.count == model.visibleItems.count ? "Deselect All" : "Select All") { withAnimation(.snappy) { model.selection = model.selection.count == model.visibleItems.count ? [] : Set(model.visibleItems.map(\.id)) } } }
                ToolbarItem(placement: .topBarTrailing) { Button("Done", role: .confirm) { finishSelection() } }
                ToolbarItem(placement: .bottomBar) { Button { perform(.share, items: selectedItems) } label: { Label("Share", systemImage: "square.and.arrow.up") }.disabled(model.selection.isEmpty) }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { perform(.copy, items: selectedItems) } label: { Label("Copy", systemImage: "doc.on.doc") }.disabled(model.selection.isEmpty)
                    Button { perform(.move, items: selectedItems) } label: { Label("Move", systemImage: "folder") }.disabled(model.selection.isEmpty)
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Menu { Button("Cut") { perform(.cut, items: selectedItems) }; Button("Duplicate") { perform(.duplicate, items: selectedItems) }; if route.location == .local { Button("Compress") { perform(.compress, items: selectedItems) } }; Button("Export to Files…") { perform(.export, items: selectedItems) }; if !selectedItems.isEmpty && selectedItems.allSatisfy({ $0.kind == .audio }) { Button("Add to Queue") { perform(.addQueue, items: selectedItems) } }; if !selectedItems.isEmpty && selectedItems.allSatisfy({ $0.kind.isMedia }) { Button("Add to Playlist…") { perform(.addPlaylist, items: selectedItems) } }; if route.location.isRemote { Button("Download to My iPhone") { perform(.download, items: selectedItems) } } } label: { Label("More", systemImage: "ellipsis.circle") }.disabled(model.selection.isEmpty)
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) { Button { deleting = selectedItems } label: { Label("Delete", systemImage: "trash") }.tint(.danger).disabled(model.selection.isEmpty) }
            } else {
                if transfers.activeCount > 0 { ToolbarItem(placement: .topBarTrailing) { Button { navigator.showTransfers = true } label: { TransferIndicator() }.accessibilityLabel("Transfers") } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu { addMenu } label: { Image(systemName: "plus") }.accessibilityLabel("Add files")
                    Menu {
                        Button { withAnimation(.smooth) { editMode = .active; searchPresented = false; selectionTrigger += 1 } } label: { Label("Select", systemImage: "checkmark.circle") }
                        Divider()
                        Picker("View", selection: $settings.viewMode) { Label("List", systemImage: "list.bullet").tag(ViewMode.list); Label("Icons", systemImage: "square.grid.2x2").tag(ViewMode.grid) }
                        Menu("Sort By") {
                            ForEach(SortKey.allCases, id: \.self) { key in
                                Button {
                                    withAnimation(.smooth) { if settings.sortKey == key { settings.sortAscending.toggle() } else { settings.sortKey = key; settings.sortAscending = key == .name || key == .kind } }
                                } label: { if settings.sortKey == key { Label(key.rawValue, systemImage: settings.sortAscending ? "chevron.up" : "chevron.down") } else { Text(key.rawValue) } }
                            }
                        }
                        Toggle("Folders on Top", isOn: $settings.foldersOnTop)
                        Toggle("Show Hidden Files", isOn: $settings.showHiddenFiles)
                        Toggle("Show Extensions", isOn: $settings.showExtensions)
                        Divider()
                        if route.location.isRemote { Button("Refresh", systemImage: "arrow.clockwise") { actions.submit { await model.reload(force: true) } } }
                        FavouriteButton(item: .folder(location: route.location, path: route.path))
                        Button("Get Info", systemImage: "info.circle") { actions.submit { if let item = try? await model.registry.provider(for: route.location).stat(route.path) { sheet = .info(item) } } }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Folder options")
                }
            }
        }
        .safeAreaInset(edge: .bottom) { if canPaste && !editMode.isEditing { PasteBar(location: route.location, path: route.path).transition(.move(edge: .bottom).combined(with: .opacity)) } }
        .mediaUpload(kind: .files, destination: route, enabled: route.location.isRemote && !editMode.isEditing)
        .sensoryFeedback(.impact(weight: .light), trigger: selectionTrigger)
        .sensoryFeedback(.warning, trigger: deleteTrigger)
        .sheet(item: $sheet, onDismiss: { if let pendingEditor { navigator.newDocument(pendingEditor); self.pendingEditor = nil } }) { content in
            switch content {
            case .rename(let item): RenameSheet(item: item, existing: model.items) { name in let result = await operations.rename(item, to: name); await model.reload(force: true); return result != nil }
            case .newItem(let folder): NewItemSheet(folder: folder, existing: Set(model.items.map(\.name))) { name in
                let item = folder ? await operations.createFolder(named: name, location: route.location, in: route.path) : FileItem(location: route.location, path: PathUtil.join(route.path, name), name: name, isDirectory: false, size: 0, modified: nil, created: nil, etag: nil, contentType: "text/markdown")
                await model.reload(force: true)
                if let item { navigator.highlightID = item.id; if !folder { pendingEditor = item } }
                return item != nil
            }
            case .info(let item): InfoSheet(item: item)
            case .destination(let items, let move, let localOnly): DestinationPicker(title: move ? "Move Here" : "Copy Here", allowedLocations: localOnly ? [.local] : nil, sources: items, move: move, initial: BrowserRoute(location: route.location, path: route.path)) { location, path in await operations.transfer(items, to: location, destDir: path, move: move); finishSelection() }
            }
        }
        .sheet(item: $share) { request in Group { if request.exporting { ExportView(urls: request.urls) } else { ActivityView(urls: request.urls) } }.presentationDetents([.medium, .large]).presentationBackground(Color.canvas) }
        .sheet(isPresented: $choosingUpload) { MediaPicker(kind: .files, allowedLocations: [.local], actionTitle: "Upload") { items in actions.submit { await operations.transfer(items, to: route.location, destDir: route.path, move: false) } } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in switch result { case .success(let urls): actions.submit { if route.location.isRemote { await transfers.enqueueExternalUploads(urls, to: route.location, dirPath: route.path) } else { _ = await importer.importFiles(urls, to: route.path, move: false) }; await model.reload(force: true) }; case .failure(let error): toast.show(error: error) } }
        .onChange(of: photos) { _, selected in actions.submit { for photo in selected { do { if let file = try await photo.loadTransferable(type: FileTransferable.self) { if route.location.isRemote { await transfers.enqueueExternalUploads([file.url], to: route.location, dirPath: route.path) } else { _ = await importer.importFiles([file.url], to: route.path, move: true) }; let temporary = file.url.deletingLastPathComponent(); await Task.detached { try? FileManager.default.removeItem(at: temporary) }.value } } catch { toast.show(error: error) } }; photos = []; await model.reload(force: true) } }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { !deleting.isEmpty }, set: { if !$0 { deleting = [] } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { let items = deleting; deleting = []; actions.submit { await operations.delete(items); deleteTrigger += 1; finishSelection(); await model.reload(force: true) } }
            Button("Cancel", role: .cancel) { deleting = [] }
        } message: { Text(route.location.isRemote ? "This will delete it from \"\(model.registry.displayName(for: route.location))\". This can't be undone." : "This can't be undone.") }
        .confirmationDialog(moreItem?.name ?? "", isPresented: Binding(get: { moreItem != nil }, set: { if !$0 { moreItem = nil } }), titleVisibility: .visible) {
            if let item = moreItem { FavouriteButton(item: item); Button("Rename") { sheet = .rename(item) }; Button("Move…") { perform(.move, items: [item]) }; Button("Share") { perform(.share, items: [item]) }; Button("Get Info") { sheet = .info(item) } }
            Button("Cancel", role: .cancel) { moreItem = nil }
        }
        .refreshable { await model.reload(force: true) }
        .task { await model.load(); if route.location == .local { watcher.start(model.registry.local.url(for: route.path)) { actions.submit { await model.reload() } } } }
        .task(id: model.query + model.scope.rawValue) { try? await Task.sleep(for: .milliseconds(200)); guard !Task.isCancelled else { return }; await model.searchEverywhere() }
        .task(id: navigator.highlightID) { if navigator.highlightID != nil { try? await Task.sleep(for: .seconds(1)); guard !Task.isCancelled else { return }; withAnimation(.smooth) { navigator.highlightID = nil } } }
        .onChange(of: model.selection) { _, selected in if !selected.isEmpty && !editMode.isEditing { withAnimation(.smooth) { editMode = .active; searchPresented = false; selectionTrigger += 1 } } }
        .onDisappear { watcher.cancel() }
        .onChange(of: phase) { _, phase in if phase == .active { actions.submit { await model.reload(force: true) } } }
        .onReceive(NotificationCenter.default.publisher(for: .cofferDirectoryChanged)) { notification in if notification.userInfo?["location"] as? LocationID == route.location && notification.userInfo?["path"] as? String == route.path { actions.submit { await model.reload(force: true) } } }
        }.managedTasks(actions)
    }
    // Empty/loading/search states occupy the scroll viewport so native search has
    // real content to lay out from the first frame, instead of a zero-height list.
    @ViewBuilder private var emptyState: some View {
        if model.isLoading && model.items.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.error, model.items.isEmpty {
            ContentUnavailableView { Label("Couldn't load this folder", systemImage: "wifi.exclamationmark") } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Try Again") { actions.submit { await model.reload(force: true) } }.buttonStyle(.glass)
            }
        } else if !model.query.isEmpty {
            ContentUnavailableView.search(text: model.query)
        } else if model.items.isEmpty {
            ContentUnavailableView { Label("This folder is empty", systemImage: "folder").foregroundStyle(Color.inkTertiary) } description: {
                Text("Tap + to add files or create a folder.")
            } actions: { Menu("Add") { addMenu }.buttonStyle(.glass) }
        } else {
            ContentUnavailableView("No visible files", systemImage: "folder", description: Text("Enable Show Hidden Files to see hidden items."))
        }
    }
    private var selectedItems: [FileItem] { model.visibleItems.filter { model.selection.contains($0.id) } }
    private var deleteTitle: String { deleting.count == 1 ? "Delete \"\(deleting[0].name)\"?" : "Delete \(deleting.count) items?" }
    private var canPaste: Bool { !clipboard.isEmpty && !clipboard.items.contains { $0.location == route.location && $0.isDirectory && PathUtil.isAncestor($0.path, of: route.path) } }
    @ViewBuilder private var addMenu: some View {
        if canPaste { Button("Paste", systemImage: "doc.on.clipboard") { actions.submit { await operations.transfer(clipboard.items, to: route.location, destDir: route.path, move: clipboard.mode == .cut); if clipboard.mode == .cut { withAnimation(.smooth) { clipboard.set(clipboard.items.filter { !operations.lastTransferredIDs.contains($0.id) }, mode: .cut) } } } }; Divider() }
        Button("New Folder", systemImage: "folder.badge.plus") { sheet = .newItem(true) }
        Button("New Markdown Document", systemImage: "doc.badge.plus") { sheet = .newItem(false) }
        Divider()
        Button("Import from Files", systemImage: "folder") { importing = true }
        PhotosPicker(selection: $photos, maxSelectionCount: nil, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current) { Label("Import from Photos", systemImage: "photo.on.rectangle") }
        if route.location.isRemote { Button("Upload from My iPhone", systemImage: "iphone.and.arrow.forward") { choosingUpload = true } }
    }
    private func tap(_ item: FileItem) {
        if editMode.isEditing { withAnimation(.snappy) { if model.selection.contains(item.id) { model.selection.remove(item.id) } else { model.selection.insert(item.id) } } }
        else { navigator.open(item, siblings: model.visibleItems) }
    }
    private func finishSelection() { withAnimation(.smooth) { editMode = .inactive; model.selection.removeAll() } }
    private func perform(_ action: FileAction, items: [FileItem]) {
        guard let item = items.first else { return }
        switch action {
        case .open: navigator.open(item, siblings: model.visibleItems)
        case .playNext: AppServices.shared.player.playNext(items.filter { $0.kind == .audio }.map(MediaRef.init)); toast.show("Playing next")
        case .addQueue: AppServices.shared.player.addToQueue(items.filter { $0.kind == .audio }.map(MediaRef.init)); toast.show("Added to queue")
        case .addPlaylist: navigator.playlistItems = items.filter { $0.kind.isMedia }.map(MediaRef.init)
        case .edit: navigator.editorItem = item
        case .copy, .cut:
            clipboard.set(items, mode: action == .cut ? .cut : .copy)
            toast.show(action == .cut ? "Cut \(items.count) items" : "Copied \(items.count) items to clipboard", symbol: "doc.on.clipboard"); finishSelection()
        case .rename: sheet = .rename(item)
        case .info: sheet = .info(item)
        case .delete: deleting = items
        case .move, .download: sheet = .destination(items, action == .move, action == .download)
        case .duplicate: actions.submit { await operations.transfer(items, to: route.location, destDir: route.path, move: false); finishSelection() }
        case .share, .export:
            actions.submit { do { let urls = try await SharePreparation.urls(for: items); share = ShareRequest(urls: urls, exporting: action == .export); finishSelection() } catch { toast.show(error: error) } }
        case .compress:
            let owner = UUID(); compressionID = owner; toast.show("Compressing…", symbol: "archivebox")
            actions.submit {
                do {
                    defer { compressionID = nil }
                    let urls = items.map { model.registry.local.url(for: $0.path) }
                    let zip = try await ZipService.compress(items: urls, into: model.registry.local.url(for: route.path), name: items.count == 1 ? item.name + ".zip" : "Archive.zip") { value in DispatchQueue.main.async { if compressionID == owner { toast.show("Compressing… \(Int(value * 100))%", symbol: "archivebox") } } }
                    compressionID = nil; operations.changed(route.location, route.path); toast.show("Created \"\(zip.lastPathComponent)\"", symbol: "checkmark"); finishSelection()
                } catch { toast.show(error: error) }
            }
        case .uncompress:
            actions.submit {
                do {
                    let local = model.registry.local
                    let zip = item.location.isRemote ? try await AppServices.shared.remoteCache.fetch(item, progress: { _ in }) : local.url(for: item.path)
                    let destination = item.location.isRemote ? "/" : item.parentPath
                    let folder = try await ZipService.uncompress(zip, into: local.url(for: destination))
                    operations.changed(.local, destination)
                    toast.show("Uncompressed to \"\(folder.lastPathComponent)\"", symbol: "checkmark", actionTitle: "Show") { navigator.reveal(location: .local, path: PathUtil.join(destination, folder.lastPathComponent)) }
                } catch { toast.show(error: error) }
            }
        case .playAll:
            actions.submit { do { let audio = try await model.registry.provider(for: item.location).list(item.path).filter { $0.kind == .audio }; if let first = audio.first { navigator.open(first, siblings: audio) } else { toast.show("No audio in this folder") } } catch { toast.show(error: error) } }
        case .offline: if AppServices.shared.remoteCache.pinned.contains(item.id) { AppServices.shared.remoteCache.unpin(item) } else { AppServices.shared.remoteCache.pin(item) }
        }
    }
    private func importDropped(_ urls: [URL], to path: String) {
        actions.submit {
            let local = model.registry.local
            if route.location == .local && urls.allSatisfy({ PathUtil.isAncestor(local.rootURL.path, of: $0.path) }) {
                var items: [FileItem] = []
                for url in urls { let relative = "/" + String(url.path.dropFirst(local.rootURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")); if let item = try? await local.stat(relative) { items.append(item) } }
                await operations.transfer(items, to: .local, destDir: path, move: true)
            } else if route.location.isRemote { await transfers.enqueueExternalUploads(urls, to: route.location, dirPath: path) } else { _ = await importer.importFiles(urls, to: path, move: false) }
        }
    }
    private var ancestors: [String] { var paths: [String] = []; var path = route.path; while path != "/" { path = PathUtil.parent(path); paths.append(path) }; if paths.isEmpty { paths = ["/"] }; return paths }
}

private enum BrowserSheet: Identifiable {
    case rename(FileItem), newItem(Bool), info(FileItem), destination([FileItem], Bool, Bool)
    var id: String { switch self { case .rename(let item): return "rename:" + item.id; case .newItem(let folder): return "new:" + String(folder); case .info(let item): return "info:" + item.id; case .destination(let items, let move, _): return "destination:" + (items.first?.id ?? "") + String(move) } }
}
