import SwiftUI

struct MarkdownFormatBar: View {
    let controller: CodeEditorController
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                format("Heading", symbol: "textformat.size") { controller.insert("## ", placeholder: "Heading") }
                format("Bold", symbol: "bold") { controller.insert("**", suffix: "**", placeholder: "bold text") }
                format("Italic", symbol: "italic") { controller.insert("*", suffix: "*", placeholder: "italic text") }
                format("Strikethrough", symbol: "strikethrough") { controller.insert("~~", suffix: "~~", placeholder: "text") }
                format("Link", symbol: "link") { controller.insert("[", suffix: "](https://example.com)", placeholder: "title") }
                format("Image", symbol: "photo") { controller.insert("![", suffix: "](image.png)", placeholder: "description") }
                format("Quote", symbol: "text.quote") { controller.insert("\n> ", placeholder: "quote") }
                format("Bullet List", symbol: "list.bullet") { controller.insert("\n- ", placeholder: "item") }
                format("Numbered List", symbol: "list.number") { controller.insert("\n1. ", placeholder: "item") }
                format("Task", symbol: "checklist") { controller.insert("\n- [ ] ", placeholder: "task") }
                format("Inline Code", symbol: "chevron.left.forwardslash.chevron.right") { controller.insert("`", suffix: "`", placeholder: "code") }
                format("Code Block", symbol: "curlybraces.square") { controller.insert("\n```\n", suffix: "\n```\n", placeholder: "code") }
                format("Table", symbol: "tablecells") { controller.insert("\n| Column 1 | Column 2 |\n| --- | --- |\n| Value | Value |\n") }
                format("Math", symbol: "function") { controller.insert("$", suffix: "$", placeholder: "x^2") }
                format("Display Math", symbol: "sum") { controller.insert("\n$$\n", suffix: "\n$$\n", placeholder: "\\frac{a}{b}") }
                format("Divider", symbol: "minus") { controller.insert("\n\n---\n\n") }
                Button { controller.textView?.resignFirstResponder() } label: { Image(systemName: "keyboard.chevron.compact.down").frame(width: 44, height: 44) }.accessibilityLabel("Hide keyboard")
            }.padding(.horizontal, 12)
        }.scrollIndicators(.hidden).background(Color.surface).buttonStyle(.plain).foregroundStyle(Color.pinkInk)
    }
    private func format(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44) }.accessibilityLabel(title)
    }
}
