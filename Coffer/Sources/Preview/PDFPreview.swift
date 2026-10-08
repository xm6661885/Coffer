import SwiftUI
import PDFKit

struct PDFPreview: View {
    let item: FileItem
    let url: URL
    @Binding var immersive: Bool
    @Environment(PlaybackPositionStore.self) private var positions
    @State private var document: PDFDocument?
    @State private var view: PDFView?
    @State private var page = 1
    @State private var showNumber = true
    @State private var continuous = true
    @State private var goToPage = false
    @State private var pageInput = ""
    var body: some View {
        Group { if let document { PDFSurface(document: document, continuous: continuous, initialPage: Int(positions.position(for: item.id)), pdfView: $view, tapped: { withAnimation(.smooth) { immersive.toggle() } }) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) } }
            .background(Color.canvas)
            .overlay(alignment: .bottom) { if showNumber && !immersive { Text("\(page) / \(document?.pageCount ?? 0)").font(.cofferTimecode).padding(.horizontal, 16).padding(.vertical, 10).glassEffect(.regular, in: .capsule).padding(16) } }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { view?.findInteraction.presentFindNavigator(showingReplace: false) } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Find in PDF")
                    Menu { Button(continuous ? "Single Page" : "Continuous") { continuous.toggle() }; Button("Go to Page…") { pageInput = "\(page)"; goToPage = true } } label: { Image(systemName: "doc.text.magnifyingglass") }.accessibilityLabel("PDF options")
                }
            }
            .alert("Go to Page…", isPresented: $goToPage) { TextField("Page number", text: $pageInput).keyboardType(.numberPad); Button("Go") { if let n = Int(pageInput), let target = document?.page(at: max(0, min((document?.pageCount ?? 1) - 1, n - 1))) { view?.go(to: target) } }; Button("Cancel", role: .cancel) { } }
            .task { document = await Task.detached { PDFDocument(url: url) }.value }
            .onReceive(NotificationCenter.default.publisher(for: .PDFViewPageChanged)) { notification in
                guard let pdf = notification.object as? PDFView, pdf === view, let current = pdf.currentPage, let doc = pdf.document else { return }
                page = doc.index(for: current) + 1; positions.save(item, time: Double(page - 1), duration: Double(doc.pageCount)); withAnimation(.smooth) { showNumber = true }
            }
            .task(id: page) { try? await Task.sleep(for: .seconds(1.5)); guard !Task.isCancelled else { return }; withAnimation(.smooth) { showNumber = false } }
    }
}
private struct PDFSurface: UIViewRepresentable {
    let document: PDFDocument; let continuous: Bool; let initialPage: Int
    @Binding var pdfView: PDFView?
    let tapped: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(tapped) }
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.document = document; view.autoScales = true; view.displayDirection = .vertical; view.usePageViewController(false); view.backgroundColor = UIColor(named: "Canvas") ?? .clear; view.pageShadowsEnabled = true; view.isFindInteractionEnabled = true
        if let page = document.page(at: initialPage) { view.go(to: page) }
        let recognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap)); recognizer.cancelsTouchesInView = false; view.addGestureRecognizer(recognizer)
        DispatchQueue.main.async { pdfView = view }
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) { view.displayMode = continuous ? .singlePageContinuous : .singlePage }
    final class Coordinator: NSObject { let tapped: () -> Void; init(_ tapped: @escaping () -> Void) { self.tapped = tapped }; @objc func tap() { tapped() } }
}
