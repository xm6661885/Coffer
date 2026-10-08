import SwiftUI
import WebKit
import SafariServices

struct WebRenderView: UIViewRepresentable {
    enum Content: Equatable { case html(String, baseURL: URL?), file(URL, readAccess: URL) }
    let content: Content
    var findEnabled = true
    @Binding var webView: WKWebView?
    var onExternalLink: ((URL) -> Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(BundleResourceSchemeHandler(), forURLScheme: BundleResourceSchemeHandler.scheme)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.dataDetectorTypes = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false; view.backgroundColor = .clear; view.scrollView.backgroundColor = .clear
        view.scrollView.contentInsetAdjustmentBehavior = .automatic; view.isFindInteractionEnabled = findEnabled
        view.navigationDelegate = context.coordinator
        DispatchQueue.main.async { webView = view }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self; view.isFindInteractionEnabled = findEnabled
        guard context.coordinator.lastContent != content else { return }
        context.coordinator.lastContent = content
        switch content { case .html(let html, let base): view.loadHTMLString(html, baseURL: base?.isFileURL == true ? BundleResourceSchemeHandler.origin : base); case .file(let file, let readAccess): view.loadFileURL(file, allowingReadAccessTo: readAccess) }
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebRenderView; var lastContent: Content?
        init(_ parent: WebRenderView) { self.parent = parent }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else { decisionHandler(.allow); return }
            if url.scheme == "https" || url.scheme == "http" { parent.onExternalLink?(url); decisionHandler(.cancel) }
            else if url.fragment != nil && url.deletingPathExtension().path == webView.url?.deletingPathExtension().path { decisionHandler(.allow) }
            else { decisionHandler(.cancel) }
        }
    }
}
struct SafariRequest: Identifiable { let id = UUID(); let url: URL }
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) { uiViewController.view.tintColor = UIColor(named: "PinkInk") }
}
