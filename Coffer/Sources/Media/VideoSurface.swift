import SwiftUI
import AVFoundation

final class AVSurfaceView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
@MainActor final class VideoSurfaceHost: UIView {
    let avView = AVSurfaceView()
    let vlcView = UIView()
    let sampleBufferLayer = AVSampleBufferDisplayLayer()
    var useAV = true
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .black; addSubview(avView); addSubview(vlcView) }
    required init?(coder: NSCoder) { super.init(coder: coder); addSubview(avView); addSubview(vlcView) }
    override func layoutSubviews() { super.layoutSubviews(); avView.frame = bounds; vlcView.frame = bounds; sampleBufferLayer.frame = vlcView.bounds }
    func configure(_ backend: PlayerBackend, fill: Bool) {
        useAV = backend is AVPlayerBackend; avView.isHidden = !useAV; vlcView.isHidden = useAV
        if let backend = backend as? AVPlayerBackend { backend.surfaceIsVisible = { [weak avView] in avView?.window != nil && (avView?.bounds.width ?? 0) > 0 && (avView?.bounds.height ?? 0) > 0 }; if avView.playerLayer.player !== backend.player { avView.playerLayer.player = backend.player }; CATransaction.begin(); CATransaction.setAnimationDuration(0.25); avView.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect; CATransaction.commit() }
        if let backend = backend as? VLCBackend {
            backend.surfaceIsVisible = { [weak vlcView] in vlcView?.window != nil && (vlcView?.bounds.width ?? 0) > 0 && (vlcView?.bounds.height ?? 0) > 0 }
            if backend.videoOutput != nil {
                if sampleBufferLayer.superlayer !== vlcView.layer { vlcView.layer.addSublayer(sampleBufferLayer) }
                sampleBufferLayer.frame = vlcView.bounds; sampleBufferLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
            } else {
                sampleBufferLayer.removeFromSuperlayer()
                backend.player.drawable = vlcView; backend.player.scaleFactor = 0
                if fill { let ratio = "\(max(1, Int(bounds.width))):\(max(1, Int(bounds.height)))"; ratio.withCString { backend.player.videoCropGeometry = UnsafeMutablePointer(mutating: $0) } }
                else { backend.player.videoCropGeometry = nil }
            }
        }
    }
}
struct VideoSurface: UIViewRepresentable {
    let model: VideoPlayerModel
    func makeUIView(context: Context) -> UIView { let wrapper = UIView(); wrapper.backgroundColor = .black; attach(to: wrapper); return wrapper }
    func updateUIView(_ uiView: UIView, context: Context) { attach(to: uiView); if !model.layerDetached { model.surface.configure(model.backend, fill: model.videoGravity == .fill) } }
    private func attach(to wrapper: UIView) { let surface = model.surface; if surface.superview !== wrapper { surface.removeFromSuperview(); wrapper.addSubview(surface); surface.translatesAutoresizingMaskIntoConstraints = false; NSLayoutConstraint.activate([surface.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor), surface.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor), surface.topAnchor.constraint(equalTo: wrapper.topAnchor), surface.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)]) }; if model.systemVolume.view.superview == nil { wrapper.addSubview(model.systemVolume.view) } }
}
