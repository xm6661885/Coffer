import SwiftUI
import UIKit

struct ActivityView: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil); controller.view.backgroundColor = UIColor(named: "Canvas"); return controller }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { uiViewController.view.backgroundColor = UIColor(named: "Canvas") }
}
struct ExportView: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController { UIDocumentPickerViewController(forExporting: urls, asCopy: true) }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) { uiViewController.view.backgroundColor = UIColor(named: "Canvas") }
}
struct ShareRequest: Identifiable { let id = UUID(); let urls: [URL]; var exporting = false }
