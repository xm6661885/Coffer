import SwiftUI
import Observation

@MainActor @Observable final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        let id = UUID(); let message: String; let symbol: String?; let actionTitle: String?; let action: (() -> Void)?
        static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
    }
    private(set) var current: Toast?
    private var dismissal: Task<Void, Never>?
    var successTrigger = 0
    func show(_ message: String, symbol: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        dismissal?.cancel()
        withAnimation(.smooth) { current = Toast(message: message, symbol: symbol, actionTitle: actionTitle, action: action) }
        if symbol == "checkmark" { successTrigger += 1 }
        dismissal = Task { try? await Task.sleep(for: .seconds(action == nil ? 2.5 : 4)); guard !Task.isCancelled else { return }; dismiss() }
    }
    func show(error: Error) { show(error.localizedDescription, symbol: "exclamationmark.triangle") }
    func dismiss() { dismissal?.cancel(); withAnimation(.smooth) { current = nil } }
}
struct ToastView: View {
    let toast: ToastCenter.Toast
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            if let symbol = toast.symbol { Image(systemName: symbol).symbolRenderingMode(.hierarchical) }
            Text(toast.message).font(.cofferCallout)
            if let title = toast.actionTitle { Button(title) { toast.action?(); dismiss() }.fontWeight(.semibold).foregroundStyle(Color.pinkInk).frame(minHeight: 44) }
        }.foregroundStyle(Color.ink).padding(.horizontal, 16).padding(.vertical, 10).glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 20).padding(.top, 8).gesture(DragGesture().onEnded { if $0.translation.height < -20 { dismiss() } })
    }
}
struct ProgressBar: View {
    var value: Double
    var height: CGFloat = 6
    @State private var moving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.pinkSoft)
                Capsule().fill(Color.pink).frame(width: value < 0 ? g.size.width * 0.3 : max(height, g.size.width * min(1, max(0, value))))
                    .offset(x: value < 0 && moving ? g.size.width * 0.7 : 0)
            }.clipped()
                .animation(value < 0 && !reduceMotion ? .linear(duration: 1.2).repeatForever(autoreverses: true) : .linear(duration: 0.25), value: moving)
                .animation(.linear(duration: 0.25), value: value)
        }.frame(height: height).onAppear { if value < 0 { moving = true } }.accessibilityValue(value < 0 ? "In progress" : "\(Int(value * 100)) percent")
    }
}
struct GlassIconButton: View {
    let title: String; let symbol: String; var action: () -> Void
    var body: some View { Button(action: action) { Image(systemName: symbol).frame(minWidth: 44, minHeight: 44) }.buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel(title) }
}
struct SectionHeader: View {
    let title: String
    var body: some View { Text(title).font(.cofferHeadline).foregroundStyle(Color.ink).frame(maxWidth: .infinity, alignment: .leading) }
}
struct EmptyState: View {
    let title: String; let symbol: String; let description: String
    var body: some View { ContentUnavailableView { Label(title, systemImage: symbol).foregroundStyle(Color.inkTertiary) } description: { Text(description).foregroundStyle(Color.inkSecondary) } }
}
