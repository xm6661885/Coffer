import SwiftUI

struct TextEditorView: View {
    @State private var actions = ViewActions()
    let item: FileItem
    @State private var model: TextEditorModel
    @State private var controller = CodeEditorController()
    @State private var watcher = DirectoryWatcher()
    @State private var renaming = false
    @State private var info = false
    @State private var sharing: ShareRequest?
    @State private var preview = false
    @State private var renderedMarkdown = false
    @State private var saveConfirmation = false
    @State private var saveName = ""
    @State private var namingDraft = false
    @State private var renderingURL: URL?
    @State private var pendingEncoding: String.Encoding?
    @State private var reloadConfirmation = false
    @Environment(AppSettings.self) private var settings
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    init(item: FileItem, isDraft: Bool = false) { self.item = item; _model = State(initialValue: TextEditorModel(item: item, services: AppServices.shared, isDraft: isDraft)) }
    var body: some View {
        @Bindable var model = model
        Group {
            NavigationStack { navigationContent }
                .task { await openEditor() }
                .onChange(of: model.text) { _, _ in if model.loaded && model.text != model.saved { model.changed() } }
                .onChange(of: phase) { _, phase in sceneChanged(phase) }
                .onChange(of: renderedMarkdown) { _, showing in if showing { controller.textView?.resignFirstResponder() } }
                .onChange(of: model.item.id) { _, _ in updateRenderingURL() }
                .onDisappear { watcher.cancel(); model.cancel() }
                .background { Button("Save") { actions.submit { _ = await model.save() } }.keyboardShortcut("s", modifiers: .command).hidden() }
                .sheet(isPresented: $renaming) { RenameSheet(item: model.item, existing: []) { name in if await model.save(), let updated = await AppServices.shared.operations.rename(model.item, to: name) { model.renamed(updated); return true }; return false } }.sheet(isPresented: $info) { InfoSheet(item: model.item) }.sheet(item: $sharing) { ActivityView(urls: $0.urls) }
                .confirmationDialog("This file changed on the server", isPresented: $model.serverConflict, titleVisibility: .visible) { Button("Overwrite", role: .destructive) { model.chooseConflict(.overwrite) }; Button("Save as Copy") { model.chooseConflict(.copy) }; Button("Cancel", role: .cancel) { model.chooseConflict(.cancel) } }
                .confirmationDialog("This file changed outside Coffer", isPresented: $model.localConflict, titleVisibility: .visible) { Button("Overwrite", role: .destructive) { model.chooseConflict(.overwrite) }; Button("Reload", role: .destructive) { model.chooseConflict(.cancel); actions.submit { await model.load() } }; Button("Cancel", role: .cancel) { model.chooseConflict(.cancel) } }
                .confirmationDialog("Couldn't save changes", isPresented: $model.saveFailure, titleVisibility: .visible) { Button("Try Again", action: saveAndClose); Button("Discard Changes", role: .destructive) { dismiss() }; Button("Cancel", role: .cancel) { } }
                .confirmationDialog("Reload and discard unsaved changes?", isPresented: $reloadConfirmation, titleVisibility: .visible) { Button("Reload", role: .destructive) { actions.submit { await model.load() } }; Button("Cancel", role: .cancel) { } }
            .confirmationDialog("Reload using this encoding and discard unsaved changes?", isPresented: Binding(get: { pendingEncoding != nil }, set: { if !$0 { pendingEncoding = nil } }), titleVisibility: .visible) { Button("Reload", role: .destructive) { if let pendingEncoding { model.changeEncoding(pendingEncoding) }; pendingEncoding = nil }; Button("Cancel", role: .cancel) { pendingEncoding = nil } }
            .confirmationDialog(model.isDraft ? "Save this Markdown document?" : "Save your changes?", isPresented: $saveConfirmation, titleVisibility: .visible) {
                Button("Save") { if model.isDraft { saveName = model.item.name; namingDraft = true } else { saveAndClose() } }
                Button(model.isDraft ? "Discard Document" : "Discard Changes", role: .destructive) { dismiss() }
                Button("Cancel", role: .cancel) { }
            }
            .alert("Save Document", isPresented: $namingDraft) {
                TextField("Filename", text: $saveName)
                Button("Save") { guard PathUtil.isValidName(saveName) else { AppServices.shared.toast.show("Choose a valid filename"); return }; model.nameDraft(saveName); saveAndClose() }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Save in \(model.item.parentPath == "/" ? AppServices.shared.registry.displayName(for: model.item.location) : model.item.parentPath)") }
            .interactiveDismissDisabled(model.edited || model.isDraft).background(Color.canvas)
        }.managedTasks(actions)
    }
    private var navigationContent: some View {
        return editingArea.background(Color.canvas).navigationTitle(model.item.name).navigationBarTitleDisplayMode(.inline).navigationSubtitle(model.status)
                .toolbarTitleMenu { if !model.isDraft { FavouriteButton(item: model.item) }; Button(model.isDraft ? "Save Document…" : "Rename", systemImage: "pencil") { if model.isDraft { saveName = model.item.name; namingDraft = true } else { renaming = true } }; Button("Show in Files", systemImage: "folder") { actions.submit { if await model.save(closing: true) { navigator.revealFile(model.item); dismiss() } } }; Button("Get Info", systemImage: "info.circle") { info = true } }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Done", action: closeEditor) }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { controller.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.disabled(!controller.canUndo || model.readOnly)
                        Button { controller.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }.disabled(!controller.canRedo || model.readOnly)
                        Button { controller.find() } label: { Label("Find and Replace", systemImage: "magnifyingglass") }
                        editorOptions
                    }
                }
                .navigationDestination(isPresented: $preview) { previewContent }
    }
    private var editingArea: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
                if supportsMarkdown {
                    Picker("Display", selection: $renderedMarkdown) { Text("Edit").tag(false); Text("Preview").tag(true) }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 8)
                }
                if model.readOnly { Text("This file is too large to edit. Opened as read-only. Showing the first 5 MB.").font(.cofferCaption).foregroundStyle(Color.inkSecondary).padding(12).frame(maxWidth: .infinity).background(Color.surfaceSunken) }
                if model.changedOutside { HStack { Text("Changed outside Coffer"); Button("Reload") { reloadConfirmation = true } }.font(.cofferCaption).padding(12).frame(maxWidth: .infinity).background(Color.pinkSoft) }
                if let failure = model.failure, !model.loaded { ContentUnavailableView("Couldn't open this file", systemImage: "exclamationmark.triangle", description: Text(failure)) } else {
                    ZStack {
                        CodeTextView(text: $model.text, controller: controller, wrap: settings.wrapLines, lineNumbers: settings.lineNumbers, textSize: settings.textSize, prose: supportsMarkdown, readOnly: model.readOnly || !model.loaded)
                            .opacity(renderedMarkdown ? 0 : 1).allowsHitTesting(!renderedMarkdown).accessibilityHidden(renderedMarkdown)
                        if supportsMarkdown && renderedMarkdown, let renderingURL {
                            TextPreview(item: model.item, url: renderingURL, mode: .markdown, initialText: model.text, showsModePicker: false)
                        }
                    }
                    if supportsMarkdown && !renderedMarkdown { MarkdownFormatBar(controller: controller).disabled(model.readOnly || !model.loaded) }
                }
            }
    }
    private var editorOptions: some View {
        @Bindable var model = model
        @Bindable var settings = settings
        return Menu { Button("Save", systemImage: "square.and.arrow.down") { actions.submit { _ = await model.save() } }; if supportsMarkdown || ["html", "htm"].contains(model.item.ext) { Button("Preview") { actions.submit { await model.preparePreview(); preview = model.previewURL != nil } } }; Toggle("Wrap Lines", isOn: $settings.wrapLines); Toggle("Line Numbers", isOn: $settings.lineNumbers); Menu("Text Size") { Picker("Text Size", selection: $settings.textSize) { ForEach([13, 15, 18], id: \.self) { Text("\($0)").tag($0) } } }; Menu("Encoding (\(encodingName))") { ForEach(TextDecoding.encodings, id: \.0) { name, encoding in Button(name) { if model.edited && !model.isDraft { pendingEncoding = encoding } else { model.changeEncoding(encoding) } } } }; Menu("Line Endings") { Button { model.crlf = false; model.changed() } label: { if !model.crlf { Label("LF", systemImage: "checkmark") } else { Text("LF") } }; Button { model.crlf = true; model.changed() } label: { if model.crlf { Label("CRLF", systemImage: "checkmark") } else { Text("CRLF") } } }; Button("Share") { actions.submit { if await model.save(), let urls = try? await SharePreparation.urls(for: [model.item]) { sharing = ShareRequest(urls: urls) } } } } label: { Label("Editor options", systemImage: "ellipsis.circle") }
    }
    @ViewBuilder private var previewContent: some View {
        if let url = model.previewURL { TextPreview(item: model.item, url: renderingURL ?? url, mode: previewMode, initialText: model.text).navigationTitle("Preview") }
    }
    private var previewMode: TextPreview.Mode { supportsMarkdown ? .markdown : .html }
    private var supportsMarkdown: Bool { model.item.kind == .markdown || model.item.kind == .text }
    private func closeEditor() { if model.isDraft || model.edited { saveConfirmation = true } else { dismiss() } }
    private func saveAndClose() { actions.submit { if await model.save(closing: true) { dismiss() } } }
    private func openEditor() async {
        await model.load()
        updateRenderingURL()
        if item.location == .local && !model.isDraft { watcher.start(AppServices.shared.registry.local.url(for: item.parentPath), onChange: externalChange) } }
    private func updateRenderingURL() { renderingURL = model.item.location.isRemote ? AppServices.shared.remoteCache.localURL(for: model.item) : AppServices.shared.registry.local.url(for: model.item.path) }
    private func externalChange() { actions.submit { () -> Void in await model.checkExternalChange() } }
    private func sceneChanged(_ phase: ScenePhase) { actions.submit { () -> Void in if phase == .active { await model.checkExternalChange() } } }
    private var encodingName: String { TextDecoding.encodings.first { $0.1 == model.encoding }?.0 ?? "UTF-16" }
}
