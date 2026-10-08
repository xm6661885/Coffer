import SwiftUI

struct RenameSheet: View {
    @State private var actions = ViewActions()
    let item: FileItem
    let existing: [FileItem]
    let onSave: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selection: TextSelection?
    @State private var changeExtension = false
    @State private var saving = false
    @FocusState private var focused: Bool
    init(item: FileItem, existing: [FileItem], onSave: @escaping (String) async -> Bool) { self.item = item; self.existing = existing; self.onSave = onSave; _name = State(initialValue: item.name) }
    private var validation: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Name can't be empty" }
        if name.contains("/") { return "Names can't contain \"/\"" }
        if !PathUtil.isValidName(name) { return "That name isn't allowed." }
        if existing.contains(where: { $0.id != item.id && $0.name.lowercased() == name.lowercased() }) { return "An item with this name already exists" }
        return nil
    }
    var body: some View {
        Group {
            NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Name", text: $name, selection: $selection).font(.cofferBody).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused).padding(14).background(Color.surfaceSunken, in: RoundedRectangle(cornerRadius: 14)).onSubmit { requestSave() }
                Text(validation ?? "Was: \(item.name)").font(.cofferCaption).foregroundStyle(validation == nil ? Color.inkSecondary : Color.danger)
                Spacer()
            }.padding(20).background(Color.canvas).navigationTitle("Rename").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { requestSave() }.disabled(validation != nil || name == item.name || saving) } }
                .task { focused = true; selection = TextSelection(range: name.startIndex..<(item.isDirectory ? name.endIndex : name.index(name.startIndex, offsetBy: PathUtil.baseName(name).count))) }
                .confirmationDialog("Change extension from \".\(item.ext)\" to \".\(PathUtil.ext(name))\"?", isPresented: $changeExtension, titleVisibility: .visible) {
                    Button("Use \".\(PathUtil.ext(name))\"") { save() }
                    Button("Keep \".\(item.ext)\"") { name = PathUtil.baseName(name) + (item.ext.isEmpty ? "" : "." + item.ext); save() }
                    Button("Cancel", role: .cancel) { }
                }
        }.presentationDetents([.height(220)]).presentationBackground(Color.canvas)
        }.managedTasks(actions)
    }
    private func requestSave() { guard validation == nil && name != item.name && !saving else { return }; if !item.isDirectory && item.ext != PathUtil.ext(name) { changeExtension = true } else { save() } }
    private func save() { saving = true; actions.submit { if await onSave(name) { dismiss() } else { saving = false } } }
}
