import SwiftUI

private struct FileConflictDialog: ViewModifier {
    let inPicker: Bool
    @Environment(FileOperations.self) private var operations
    func body(content: Content) -> some View {
        content.confirmationDialog("\"\(operations.conflict?.name ?? "")\" already exists", isPresented: Binding(get: { operations.conflict != nil && (operations.conflictPickerCount > 0) == inPicker }, set: { if !$0 && (operations.conflictPickerCount > 0) == inPicker { operations.conflict?.resume(.cancel, false) } }), titleVisibility: .visible) {
            if let prompt = operations.conflict {
                Button("Replace", role: .destructive) { prompt.resume(.replace, false) }
                Button("Keep Both") { prompt.resume(.keepBoth, false) }
                Button("Skip") { prompt.resume(.skip, false) }
                if prompt.remaining > 0 { Button("Replace All", role: .destructive) { prompt.resume(.replace, true) }; Button("Keep Both for All") { prompt.resume(.keepBoth, true) } }
                Button("Cancel", role: .cancel) { prompt.resume(.cancel, false) }
            }
        }
    }
}
extension View { func fileConflictDialog(inPicker: Bool) -> some View { modifier(FileConflictDialog(inPicker: inPicker)) } }
