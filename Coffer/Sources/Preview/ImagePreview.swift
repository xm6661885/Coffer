import SwiftUI
import ImageIO
import CoreImage
import WebKit

struct ImagePreview: View {
    let item: FileItem
    let siblings: [FileItem]
    @Binding var immersive: Bool
    var onPageChanged: (FileItem) -> Void = { _ in }
    @State private var currentID: String
    @State private var scrollID: String?
    init(item: FileItem, siblings: [FileItem], immersive: Binding<Bool>, onPageChanged: @escaping (FileItem) -> Void = { _ in }) { self.onPageChanged = onPageChanged; self.item = item; self.siblings = siblings; _immersive = immersive; _currentID = State(initialValue: item.id); _scrollID = State(initialValue: item.id) }
    private var images: [FileItem] { let result = siblings.filter { $0.kind == .image }; return result.contains(item) ? result : [item] }
    var body: some View {
        // Native paging scroll view: lazily builds neighbours and keeps the drag on UIScrollView's own
        // deceleration. Page changes are reported only once scrolling settles, so the parent's
        // re-render (title, file stat, toolbar state) never lands mid-swipe.
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) { ForEach(images) { image in ImagePage(item: image, tapped: { withAnimation(.smooth) { immersive.toggle() } }).containerRelativeFrame([.horizontal, .vertical]).id(image.id) } }
                .scrollTargetLayout()
        }
            .scrollTargetBehavior(.paging).scrollIndicators(.hidden).scrollPosition(id: $scrollID).ignoresSafeArea(.container, edges: .horizontal)
            .background(Color.canvas)
            .onScrollPhaseChange { _, phase in if phase == .idle, let id = scrollID, id != currentID { currentID = id } }
            .onChange(of: currentID) { _, id in if let item = images.first(where: { $0.id == id }) { onPageChanged(item) } }
            .navigationTitle(images.first { $0.id == currentID }?.name ?? item.name)
            .safeAreaInset(edge: .bottom) { if !immersive { Text("\((images.firstIndex { $0.id == currentID } ?? 0) + 1) of \(images.count)").font(.cofferCaption).foregroundStyle(Color.inkSecondary).padding(8) } }
    }
}
private struct ImagePage: View {
    let item: FileItem; let tapped: () -> Void
    @Environment(ToastCenter.self) private var toast
    @State private var image: UIImage?
    @State private var web: WKWebView?
    @State private var svg: String?
    var body: some View {
        Group { if let image { ZoomableImage(image: image, tapped: tapped) } else if let svg { WebRenderView(content: .html(svg, baseURL: nil), webView: $web).onTapGesture(perform: tapped) } else { ProgressView() } }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.canvas)
            .task(id: item.id) {
                do {
                    let url: URL
                    if item.location.isRemote { url = try await AppServices.shared.remoteCache.fetch(item, progress: { _ in }) } else { url = AppServices.shared.registry.local.url(for: item.path) }
                    if item.ext == "svg" { let data = try await Task.detached { try Data(contentsOf: url) }.value; svg = "<html><meta name='viewport' content='width=device-width'><body style='margin:0;display:grid;place-items:center;height:100vh'><img style='max-width:100%;max-height:100%' src='data:image/svg+xml;base64,\(data.base64EncodedString())'></body></html>" }
                    else { let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen; let pixelSize = Int(max(screen?.nativeBounds.width ?? 1000, screen?.nativeBounds.height ?? 1000) * 3); image = try await Task.detached { try ImageLoader.load(url, maxPixelSize: pixelSize) }.value }
                } catch { toast.show(error: error) }
            }
    }
}
enum ImageLoader {
    static func load(_ url: URL, maxPixelSize: Int = 6000) throws -> UIImage {
        if ["raw", "dng", "cr2", "nef", "arw"].contains(url.pathExtension.lowercased()), let filter = CIRAWFilter(imageURL: url), let output = filter.outputImage, let cg = CIContext().createCGImage(output, from: output.extent) { return UIImage(cgImage: cg) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw FileProviderError.other("Couldn't open this image.") }
        let count = CGImageSourceGetCount(source)
        if url.pathExtension.lowercased() == "gif" && count > 1 {
            var frames: [UIImage] = []; var duration = 0.0
            for index in 0..<count {
                if let cg = CGImageSourceCreateImageAtIndex(source, index, nil) { frames.append(UIImage(cgImage: cg)) }
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                duration += max(0.02, gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? gif?[kCGImagePropertyGIFDelayTime] as? Double ?? 0.1)
            }
            if let animated = UIImage.animatedImage(with: frames, duration: duration) { return animated }
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0, height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        if width * height > 40_000_000, let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixelSize, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) { return UIImage(cgImage: cg) }
        guard let image = UIImage(contentsOfFile: url.path) else { throw FileProviderError.other("Couldn't open this image.") }
        return image.preparingForDisplay() ?? image
    }
}
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage; let tapped: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(tapped) }
    func makeUIView(context: Context) -> ImageScrollView {
        let view = ImageScrollView(); view.minimumZoomScale = 1; view.maximumZoomScale = 6; view.delegate = context.coordinator
        view.contentInsetAdjustmentBehavior = .never
        view.showsHorizontalScrollIndicator = false; view.showsVerticalScrollIndicator = false
        view.delaysContentTouches = false
        view.updatePanAvailability()
        view.imageView.image = image; view.imageView.contentMode = .scaleAspectFit; view.addSubview(view.imageView); view.backgroundColor = UIColor(named: "Canvas")
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:))); double.numberOfTapsRequired = 2
        let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTap)); single.require(toFail: double)
        view.addGestureRecognizer(double); view.addGestureRecognizer(single)
        return view
    }
    func updateUIView(_ view: ImageScrollView, context: Context) {
        context.coordinator.tapped = tapped
        if view.imageView.image !== image { view.setZoomScale(1, animated: false); view.imageView.image = image; view.contentOffset = .zero; view.setNeedsLayout() }
        view.updatePanAvailability()
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var tapped: () -> Void
        init(_ tapped: @escaping () -> Void) { self.tapped = tapped }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? ImageScrollView)?.imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { guard let view = scrollView as? ImageScrollView else { return }; view.updatePanAvailability(); view.imageView.center = CGPoint(x: max(view.bounds.width, view.contentSize.width) / 2, y: max(view.bounds.height, view.contentSize.height) / 2) }
        @objc func singleTap() { tapped() }
        @objc func doubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? ImageScrollView else { return }
            if view.zoomScale > 1 { view.setZoomScale(1, animated: true) }
            else { let point = recognizer.location(in: view.imageView), width = view.bounds.width / 2.5, height = view.bounds.height / 2.5; view.zoom(to: CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height), animated: true) }
        }
    }
}
private final class ImageScrollView: UIScrollView {
    let imageView = UIImageView()
    func updatePanAvailability() {
        // At fitted size, a one-finger drag belongs to the outer native page view.
        // Pinching/double-tapping still zooms; panning resumes once magnified.
        let magnified = zoomScale > minimumZoomScale + 0.01
        panGestureRecognizer.isEnabled = magnified
        bounces = magnified
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(zoomScale - minimumZoomScale) < 0.001 { imageView.frame = CGRect(origin: .zero, size: bounds.size); contentSize = bounds.size }
    }
}
