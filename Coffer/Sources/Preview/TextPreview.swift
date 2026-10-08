import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct TextPreview: View {
    enum Mode { case markdown, html, code, data, plain }
    let item: FileItem
    let url: URL
    var mode: Mode
    var initialText: String? = nil
    var showsModePicker = true
    @Environment(AppSettings.self) private var settings
    @Environment(ToastCenter.self) private var toast
    @Environment(\.colorScheme) private var scheme
    @State private var raw: Data?
    @State private var rendered = true
    @State private var preferred: String.Encoding?
    @State private var content: WebRenderView.Content?
    @State private var webView: WKWebView?
    @State private var safari: SafariRequest?
    @State private var banner: String?
    private var supportsRendered: Bool { mode == .markdown || mode == .html || ["json", "csv", "tsv"].contains(item.ext) }
    private var renderKey: String { "\(rendered)-\(scheme)-\(settings.wrapLines)-\(settings.previewTextSize)-\(preferred?.rawValue ?? 0)-\(initialText ?? "")" }
    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 0) {
            if supportsRendered && showsModePicker {
                Picker("Display", selection: $rendered) { Text("Rendered").tag(true); Text("Source").tag(false) }
                    .pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 8)
            }
            if let banner { Text(banner).font(.cofferCaption).foregroundStyle(Color.inkSecondary).padding(12).frame(maxWidth: .infinity).background(Color.surfaceSunken) }
            if let content { WebRenderView(content: content, webView: $webView, onExternalLink: { safari = SafariRequest(url: $0) }) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.background(Color.canvas)
            .navigationSubtitle(supportsRendered ? item.name : Formatters.bytes(item.size))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { webView?.findInteraction?.presentFindNavigator(showingReplace: false) } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Find")
                    Menu {
                        Toggle("Wrap Lines", isOn: $settings.wrapLines)
                        Menu("Text Size") { ForEach([11, 13, 16], id: \.self) { size in Button(size == 11 ? "Smaller" : size == 13 ? "Default" : "Larger") { settings.previewTextSize = size } } }
                        Menu("Encoding") { Button("Auto") { preferred = nil }; ForEach(TextDecoding.encodings, id: \.0) { name, encoding in Button { preferred = encoding } label: { if preferred == encoding { Label(name, systemImage: "checkmark") } else { Text(name) } } } }
                    } label: { Image(systemName: "textformat.size") }.accessibilityLabel("Text options")
                }
            }
            .task { rendered = UserDefaults.standard.object(forKey: "previewMode." + item.ext) as? Bool ?? true }
            .task(id: renderKey) { await render() }
            .onChange(of: rendered) { _, value in UserDefaults.standard.set(value, forKey: "previewMode." + item.ext) }
            .sheet(item: $safari) { SafariView(url: $0.url) }
    }
    private func render() async {
        do {
            let data: Data
            if let initialText { data = Data(initialText.utf8) } else if let raw { data = raw } else { data = try await TextDecoding.readPrefix(url); raw = data }
            let preferred = preferred, rendered = rendered && supportsRendered, dark = scheme == .dark, wrap = settings.wrapLines, size = settings.previewTextSize, ext = item.ext, mode = mode, url = url
            let result = try await Task.detached { () -> (WebRenderView.Content, String?) in
                var text = TextDecoding.decode(data, preferred: preferred).text
                if rendered && mode == .html { return (.file(url, readAccess: url.deletingLastPathComponent()), nil) }
                var banner: String?
                if rendered && mode == .markdown { text = TextTemplates.inlineImages(text, directory: url.deletingLastPathComponent()) }
                if rendered && ext == "json" {
                    do { let object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed); let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .withoutEscapingSlashes, .fragmentsAllowed]); text = String(decoding: pretty, as: UTF8.self) }
                    catch { banner = "This file isn't valid JSON." }
                }
                let html = try TextTemplates.page(text: text, ext: ext, rendered: rendered, markdown: mode == .markdown, dark: dark, wrap: wrap, size: size, highlight: data.count < 1024 * 1024)
                return (.html(html, baseURL: Bundle.main.resourceURL), banner)
            }.value
            try Task.checkCancellation()
            content = result.0; banner = result.1 ?? ((item.size ?? 0) > 5 * 1024 * 1024 ? "Showing the first 5 MB." : nil)
        } catch is CancellationError { } catch { toast.show(error: error) }
    }
}
