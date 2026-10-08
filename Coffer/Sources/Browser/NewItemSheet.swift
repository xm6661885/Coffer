import SwiftUI

struct NewItemSheet: View {
    @State private var actions = ViewActions()
    var folder: Bool
    let existing: Set<String>
    var title: String? = nil
    let onCreate: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selection: TextSelection?
    @State private var creating = false
    @FocusState private var focused: Bool
    var body: some View {
        Group {
            NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Name", text: $name, selection: $selection).font(.cofferBody).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused).padding(14).background(Color.surfaceSunken, in: RoundedRectangle(cornerRadius: 14)).onSubmit { create() }
                if !PathUtil.isValidName(name) { Text("That name isn't allowed.").font(.cofferCaption).foregroundStyle(Color.danger) }
                else if existing.contains(where: { $0.lowercased() == name.lowercased() }) { Text("An item with this name already exists").font(.cofferCaption).foregroundStyle(Color.danger) }
                Spacer()
            }.padding(20).background(Color.canvas).navigationTitle(title ?? (folder ? "New Folder" : "New Markdown Document")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Create") { create() }.disabled(!valid || creating) } }
                .task { name = PathUtil.uniqueName(folder ? "New Folder" : "Untitled.md", existing: existing, isDirectory: folder); focused = true; selection = TextSelection(range: name.startIndex..<(folder ? name.endIndex : name.index(name.startIndex, offsetBy: PathUtil.baseName(name).count))) }
        }.presentationDetents([.height(220)]).presentationBackground(Color.canvas)
        }.managedTasks(actions)
    }
    private var valid: Bool { PathUtil.isValidName(name) && !existing.contains(where: { $0.lowercased() == name.lowercased() }) }
    private func create() { guard valid && !creating else { return }; creating = true; actions.submit { if await onCreate(name) { dismiss() } else { creating = false } } }
}
