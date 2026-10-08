import SwiftUI
import UIKit

struct VideoGestureLayer: UIViewRepresentable {
    let model: VideoPlayerModel
    func makeUIView(context: Context) -> VideoGestureView { VideoGestureView(model: model) }
    func updateUIView(_ uiView: VideoGestureView, context: Context) { uiView.model = model }
}
final class VideoGestureView: UIView, UIGestureRecognizerDelegate {
    var model: VideoPlayerModel
    private var startTime = 0.0
    private var startVolume: Float = 0
    private var startBrightness: CGFloat = 0
    private var horizontal = false
    private var left = false
    private var top = false
    private var origin = CGPoint.zero
    private var targetTime = 0.0
    private var seekAllowed = true
    init(model: VideoPlayerModel) {
        self.model = model; super.init(frame: .zero)
        let single = UITapGestureRecognizer(target: self, action: #selector(tap))
        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTap)); double.numberOfTapsRequired = 2; single.require(toFail: double)
        let long = UILongPressGestureRecognizer(target: self, action: #selector(longPress)); long.minimumPressDuration = 0.4
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan)); pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch))
        for recognizer in [single, double, long, pan, pinch] { recognizer.delegate = self; addGestureRecognizer(recognizer) }
    }
    required init?(coder: NSCoder) { return nil }
    @objc private func tap(_ recognizer: UITapGestureRecognizer) { if model.isLocked { model.controlsVisible = true; model.resetAutoHide() } else { model.showControls() } }
    @objc private func doubleTap(_ recognizer: UITapGestureRecognizer) { model.doubleTap(at: recognizer.location(in: self).x / max(1, bounds.width)) }
    @objc private func longPress(_ recognizer: UILongPressGestureRecognizer) { guard !model.isLocked else { return }; switch recognizer.state { case .began: origin = recognizer.location(in: self); model.boost(true); case .changed: model.boost(true, translation: recognizer.location(in: self).x - origin.x); default: model.boost(false) } }
    @objc private func pinch(_ recognizer: UIPinchGestureRecognizer) { guard !model.isLocked else { return }; if recognizer.state == .changed { model.videoGravity = recognizer.scale > 1 ? .fill : .fit }; if recognizer.state == .ended { model.resetAutoHide() } }
    @objc private func pan(_ recognizer: UIPanGestureRecognizer) {
        guard !model.isLocked && !model.temporarySpeedBoost else { return }
        let delta = recognizer.translation(in: self)
        switch recognizer.state {
        case .began:
            let at = recognizer.location(in: self), speed = recognizer.velocity(in: self)
            horizontal = abs(speed.x) > abs(speed.y); seekAllowed = at.y >= bounds.height * 0.1 && at.y <= bounds.height * 0.9; left = at.x < bounds.width / 2; top = at.y < bounds.height / 4
            startTime = model.currentTime; targetTime = startTime; startVolume = model.systemVolume.value; startBrightness = window?.windowScene?.screen.brightness ?? 0.5
            model.controlsVisible = false
        case .changed:
            if horizontal && seekAllowed { targetTime = max(0, min(model.duration, startTime + Double(delta.x) * 0.2)); let change = targetTime - startTime; model.showHUD("\(change >= 0 ? "+" : "-")\(Formatters.duration(abs(change)))\n\(Formatters.duration(targetTime)) / \(Formatters.duration(model.duration))", value: targetTime / max(1, model.duration), symbol: "arrow.left.arrow.right", duration: 10) }
            else if !horizontal && !top {
                if left { let value = max(0, min(1, startBrightness - delta.y / max(1, bounds.height))); window?.windowScene?.screen.brightness = value; model.showHUD("\(Int(value * 100))%", value: Double(value), symbol: "sun.max.fill", duration: 10, style: .brightness) }
                else { let value = max(0, min(1, startVolume - Float(delta.y / max(1, bounds.height)))); model.systemVolume.set(value); model.showHUD("\(Int(value * 100))%", value: Double(value), symbol: "speaker.wave.2.fill", duration: 10, style: .volume) }
            }
        case .ended, .cancelled:
            if top && !horizontal && delta.y > 80 && recognizer.velocity(in: self).y > 500 { model.exitPlayer() }
            else if horizontal && seekAllowed { model.seek(to: targetTime) }
            model.gestureHUD = nil; model.resetAutoHide()
        default: break
        }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { gestureRecognizer is UILongPressGestureRecognizer || otherGestureRecognizer is UILongPressGestureRecognizer }
}
