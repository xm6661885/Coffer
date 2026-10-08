import SwiftUI
import QuickLook

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url) }
    func makeUIViewController(context: Context) -> QLPreviewController { let controller = QLPreviewController(); controller.dataSource = context.coordinator; controller.view.backgroundColor = UIColor(named: "Canvas"); return controller }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) { if context.coordinator.url != url { context.coordinator.url = url; controller.reloadData() } }
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(_ url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
