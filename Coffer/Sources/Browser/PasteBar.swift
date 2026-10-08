import SwiftUI

struct PasteBar: View {
    @State private var actions = ViewActions()
    let location: LocationID
    let path: String
    @Environment(Clipboard.self) private var clipboard
    @Environment(FileOperations.self) private var operations
    @Namespace private var glass
    var body: some View {
        Group {
            GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button { actions.submit { await operations.transfer(clipboard.items, to: location, destDir: path, move: clipboard.mode == .cut); if clipboard.mode == .cut { withAnimation(.smooth) { clipboard.set(clipboard.items.filter { !operations.lastTransferredIDs.contains($0.id) }, mode: .cut) } } } } label: {
                    Label("\(clipboard.items.count) items · Paste here", systemImage: "doc.on.clipboard").foregroundStyle(Color.onPink).padding(.horizontal, 16).frame(minHeight: 44)
                }.glassEffect(.regular.tint(.pink).interactive(), in: .capsule).glassEffectID("paste", in: glass)
                Button { withAnimation(.smooth) { clipboard.clear() } } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.glassEffect(.regular.interactive(), in: .circle).glassEffectID("clear", in: glass).accessibilityLabel("Clear clipboard")
            }
        }.padding(12)
        }.managedTasks(actions)
    }
}
