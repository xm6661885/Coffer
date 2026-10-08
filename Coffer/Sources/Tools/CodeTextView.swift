import SwiftUI
import UIKit
import Observation

@MainActor @Observable final class CodeEditorController {
    weak var textView: UITextView?
    var canUndo = false; var canRedo = false
    func update() { canUndo = textView?.undoManager?.canUndo ?? false; canRedo = textView?.undoManager?.canRedo ?? false }
    func undo() { textView?.undoManager?.undo(); update() }
    func redo() { textView?.undoManager?.redo(); update() }
    func find() { textView?.findInteraction?.presentFindNavigator(showingReplace: true) }
    func insert(_ prefix: String, suffix: String = "", placeholder: String = "") {
        guard let view = textView, view.isEditable, let range = view.selectedTextRange else { return }
        view.becomeFirstResponder()
        let start = view.offset(from: view.beginningOfDocument, to: range.start)
        let selection = view.text(in: range) ?? "", body: String
        body = selection.isEmpty ? placeholder : selection
        view.insertText(prefix + body + suffix)
        view.selectedRange = NSRange(location: start + (prefix as NSString).length, length: (body as NSString).length)
        view.delegate?.textViewDidChange?(view); update()
    }
}
struct CodeTextView: UIViewRepresentable {
    @Binding var text: String
    let controller: CodeEditorController
    var wrap: Bool; var lineNumbers: Bool; var textSize: Int; var prose: Bool; var readOnly: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> LineNumberTextView {
        let view = LineNumberTextView(); view.delegate = context.coordinator; view.isFindInteractionEnabled = true; view.smartQuotesType = .no; view.smartDashesType = .no; view.autocapitalizationType = .none
        view.backgroundColor = UIColor(named: "Canvas"); view.textColor = UIColor(named: "Ink"); view.text = text; if !prose { view.installAccessory() }; controller.textView = view; updateUIView(view, context: context); return view
    }
    func updateUIView(_ view: LineNumberTextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { let range = view.selectedRange; view.text = text; view.selectedRange = NSRange(location: min(range.location, (text as NSString).length), length: 0) }
        view.font = UIFont.monospacedSystemFont(ofSize: CGFloat(textSize), weight: .regular); view.showsLineNumbers = lineNumbers; view.rebuildLines()
        view.isEditable = !readOnly; view.autocorrectionType = prose ? .yes : .no; view.spellCheckingType = prose ? .yes : .no
        view.textContainer.widthTracksTextView = wrap
        view.textContainer.size = CGSize(width: wrap ? max(1, view.bounds.width - view.textContainerInset.left - view.textContainerInset.right) : 100_000, height: .greatestFiniteMagnitude)
        view.setNeedsDisplay()
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeTextView
        init(_ parent: CodeTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text; (textView as? LineNumberTextView)?.rebuildLines(); parent.controller.update() }
        func textViewDidChangeSelection(_ textView: UITextView) { parent.controller.update() }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { scrollView.setNeedsDisplay() }
    }
}
final class LineNumberTextView: UITextView {
    var showsLineNumbers = true
    private var lineStarts = [0]
    private var indexedText: String?
    private var gutterWidth: CGFloat = 40
    func rebuildLines() {
        let needsIndex = indexedText != text; indexedText = text
        let text = text as NSString
        if needsIndex { lineStarts = [0]
        for index in 0..<text.length where text.character(at: index) == 10 { lineStarts.append(index + 1) }
        }
        let digits = max(3, String(lineStarts.count).count); let numberFont = UIFont.monospacedSystemFont(ofSize: (font?.pointSize ?? 15) * 0.85, weight: .regular)
        gutterWidth = CGFloat(digits) * ("0" as NSString).size(withAttributes: [.font: numberFont]).width + 20
        textContainerInset = UIEdgeInsets(top: 12, left: showsLineNumbers ? gutterWidth + 16 : 16, bottom: 40, right: 16); setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        super.draw(rect); guard showsLineNumbers else { return }
        let gutter = CGRect(x: contentOffset.x, y: contentOffset.y, width: gutterWidth, height: bounds.height)
        (UIColor(named: "Canvas") ?? .clear).setFill(); UIRectFill(gutter)
        (UIColor(named: "Hairline") ?? .clear).setFill(); UIRectFill(CGRect(x: gutter.maxX, y: gutter.minY, width: 0.5, height: gutter.height))
        let range = layoutManager.glyphRange(forBoundingRect: CGRect(x: contentOffset.x, y: max(0, contentOffset.y - textContainerInset.top), width: bounds.width, height: bounds.height), in: textContainer)
        let numberFont = UIFont.monospacedSystemFont(ofSize: (font?.pointSize ?? 15) * 0.85, weight: .regular)
        layoutManager.enumerateLineFragments(forGlyphRange: range) { _, used, _, glyphRange, _ in
            let character = self.layoutManager.characterIndexForGlyph(at: glyphRange.location)
            var low = 0, high = self.lineStarts.count
            while low < high { let mid = (low + high) / 2; if self.lineStarts[mid] <= character { low = mid + 1 } else { high = mid } }
            let logical = max(0, low - 1); guard self.lineStarts[logical] == character else { return }
            let number = "\(logical + 1)" as NSString; let size = number.size(withAttributes: [.font: numberFont]); let x = self.contentOffset.x + self.gutterWidth - size.width - 10
            number.draw(at: CGPoint(x: x, y: used.minY + self.textContainerInset.top), withAttributes: [.font: numberFont, .foregroundColor: UIColor(named: "InkTertiary") ?? .clear])
        }
    }
    func installAccessory() {
        let accessory = UIInputView(frame: CGRect(x: 0, y: 0, width: 0, height: 44), inputViewStyle: .keyboard)
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; scroll.showsHorizontalScrollIndicator = false; accessory.addSubview(scroll)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: accessory.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: accessory.trailingAnchor), scroll.topAnchor.constraint(equalTo: accessory.topAnchor), scroll.bottomAnchor.constraint(equalTo: accessory.bottomAnchor)])
        let stack = UIStackView(); stack.axis = .horizontal; stack.spacing = 6; stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8), stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8), stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor), stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)])
        for token in ["Tab", "Left", "Right", "{", "}", "(", ")", "[", "]", "\"", "'", "<", ">", "/", "\\", "#", "*", "-", "=", ":", ";", "|", "Hide Keyboard"] {
            var configuration = UIButton.Configuration.gray(); configuration.baseForegroundColor = UIColor(named: "Ink"); configuration.cornerStyle = .small
            if token == "Left" || token == "Right" { configuration.image = UIImage(systemName: token == "Left" ? "arrow.left" : "arrow.right") }
            else if token == "Hide Keyboard" { configuration.image = UIImage(systemName: "keyboard.chevron.compact.down") } else { configuration.title = token }
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in guard let self else { return }; if token == "Hide Keyboard" { self.resignFirstResponder() } else if token == "Left" || token == "Right" { self.selectedRange = NSRange(location: max(0, min((self.text as NSString).length, self.selectedRange.location + (token == "Left" ? -1 : 1))), length: 0) } else { self.insertText(token == "Tab" ? (self.text.components(separatedBy: "\n").contains { $0.hasPrefix("\t") } ? "\t" : "    ") : token) } }); button.accessibilityLabel = token; button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true; button.heightAnchor.constraint(equalToConstant: 44).isActive = true; stack.addArrangedSubview(button)
        }
        inputAccessoryView = accessory
    }
}
