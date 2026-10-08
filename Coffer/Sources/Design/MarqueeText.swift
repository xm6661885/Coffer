import SwiftUI
import UIKit

/// Scrolls only overflowing names; keeps one readable, accessible label.
struct MarqueeText: UIViewRepresentable {
    let text: String
    var style: UIFont.TextStyle = .body
    var color: Color = .ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    func makeUIView(context: Context) -> MarqueeLabel { MarqueeLabel() }
    func updateUIView(_ view: MarqueeLabel, context: Context) {
        _ = typeSize
        view.configure(text: text, font: .preferredFont(forTextStyle: style), color: UIColor(color), animated: !reduceMotion && scenePhase == .active && !UIAccessibility.isVoiceOverRunning)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MarqueeLabel, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.label.intrinsicContentSize.width, height: uiView.label.font.lineHeight.rounded(.up))
    }
}
final class MarqueeLabel: UIView {
    let label = UILabel()
    private var animated = false
    private var animationDistance: CGFloat = -1
    override init(frame: CGRect) {
        super.init(frame: frame); clipsToBounds = true; isAccessibilityElement = true; isUserInteractionEnabled = false
        label.numberOfLines = 1; label.isAccessibilityElement = false; addSubview(label)
    }
    required init?(coder: NSCoder) { nil }
    func configure(text: String, font: UIFont, color: UIColor, animated: Bool) {
        let changed = label.text != text || label.font != font || self.animated != animated
        label.text = text; label.font = font; label.textColor = color
        accessibilityLabel = text; self.animated = animated
        if changed { label.layer.removeAnimation(forKey: "scrollName"); animationDistance = -1 }
        setNeedsLayout(); invalidateIntrinsicContentSize()
    }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: label.font.lineHeight.rounded(.up)) }
    override func didMoveToWindow() { super.didMoveToWindow(); animationDistance = -1; label.layer.removeAnimation(forKey: "scrollName"); setNeedsLayout() }
    override func layoutSubviews() {
        super.layoutSubviews()
        let width = label.intrinsicContentSize.width
        label.frame = CGRect(x: 0, y: 0, width: max(bounds.width, width), height: bounds.height)
        let distance = animated && window != nil && bounds.width > 0 ? max(0, width - bounds.width) : 0
        guard abs(distance - animationDistance) > 0.5 else { return }
        animationDistance = distance; label.layer.removeAnimation(forKey: "scrollName")
        guard distance > 1 else { return }
        let travel = Double(distance / 25), pause = 1.6, duration = travel * 2 + pause * 3
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, 0, -distance, -distance, 0, 0]
        animation.keyTimes = [0, pause / duration, (pause + travel) / duration, (pause * 2 + travel) / duration, (pause * 2 + travel * 2) / duration, 1].map { NSNumber(value: $0) }
        animation.duration = duration; animation.repeatCount = .infinity; animation.calculationMode = .linear
        label.layer.add(animation, forKey: "scrollName")
    }
}
