import SwiftUI
import UIKit

struct DocumentInteractionView: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> DocumentHost {
        let host = DocumentHost(); host.view.backgroundColor = UIColor(named: "Canvas"); host.show = { [weak host] in guard let host else { return }; context.coordinator.open(from: host) }; return host
    }
    func updateUIViewController(_ uiViewController: DocumentHost, context: Context) { uiViewController.view.backgroundColor = UIColor(named: "Canvas") }
    final class Coordinator: NSObject, UIDocumentInteractionControllerDelegate {
        let controller: UIDocumentInteractionController
        init(url: URL) { controller = UIDocumentInteractionController(url: url); super.init(); controller.delegate = self }
        func open(from host: UIViewController) {
            if !controller.presentOptionsMenu(from: CGRect(x: host.view.bounds.midX, y: 20, width: 1, height: 1), in: host.view, animated: true) {
                let share = UIActivityViewController(activityItems: [controller.url as Any], applicationActivities: nil)
                share.popoverPresentationController?.sourceView = host.view; share.popoverPresentationController?.sourceRect = host.view.bounds
                host.present(share, animated: true)
            }
        }
    }
}
final class DocumentHost: UIViewController {
    var show: (() -> Void)?
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); show?(); show = nil }
}
