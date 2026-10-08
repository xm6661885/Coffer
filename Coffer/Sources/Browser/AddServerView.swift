import SwiftUI

struct AddServerView: View {
    @State private var actions = ViewActions()
    var server: WebDAVServer? = nil
    @Environment(FileProviderRegistry.self) private var registry
    @Environment(ToastCenter.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var passwordVisible = false
    @State private var initialPath = "/"
    @State private var allowSelfSigned = false
    @State private var connections = 4
    @State private var testing = false
    @State private var saving = false
    @State private var result: String?
    @State private var connected = false
    var body: some View {
        Group {
            NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Home NAS"))
                    TextField("URL", text: $address, prompt: Text("https://example.com/dav")).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }.listRowBackground(Color.surface)
                Section("Account") {
                    TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    HStack { if passwordVisible { TextField("Password", text: $password).textInputAutocapitalization(.never).autocorrectionDisabled() } else { SecureField("Password", text: $password) }; Button { passwordVisible.toggle() } label: { Image(systemName: passwordVisible ? "eye.slash" : "eye").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel(passwordVisible ? "Hide password" : "Show password") }
                }.listRowBackground(Color.surface)
                Section("Options") {
                    TextField("Start in folder", text: $initialPath).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("Allow self-signed certificates", isOn: $allowSelfSigned)
                    Stepper("Parallel connections per download: \(connections)", value: $connections, in: 1...8)
                }.listRowBackground(Color.surface)
                Section {
                    Button { actions.submit { await test() } } label: { if testing { HStack { ProgressView(); Text("Connecting…") } } else { Text("Test Connection").foregroundStyle(Color.pinkInk) } }.disabled(testing || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let result { Label(result, systemImage: connected ? "checkmark.circle.fill" : "xmark.octagon.fill").foregroundStyle(connected ? Color.success : Color.danger).font(.cofferCallout) }
                }.listRowBackground(Color.surface)
            }.paperList().navigationTitle(server == nil ? "New Server" : "Edit Server").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button { actions.submit { await save() } } label: { Text("Save").foregroundStyle(Color.onPink) }.buttonStyle(.glassProminent).tint(.pink).disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving) } }
                .task { if let server { name = server.name; address = server.baseURL.absoluteString; username = server.username; password = registry.password(for: server.id); initialPath = server.initialPath; allowSelfSigned = server.allowSelfSigned; connections = server.connectionsPerDownload } }
        }.presentationBackground(Color.canvas)
        }.managedTasks(actions)
    }
    private func configuration() throws -> WebDAVServer {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        text = text.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard let url = URL(string: text), let host = url.host, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.query == nil, url.fragment == nil, url.user == nil, url.password == nil else { throw FileProviderError.other("Enter a valid HTTP or HTTPS server URL. Put credentials in Account.") }
        guard !PathUtil.components(initialPath).contains(where: { $0 == "." || $0 == ".." }) else { throw FileProviderError.invalidName }
        var result = WebDAVServer(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? host : name, baseURL: url, username: username, initialPath: PathUtil.normalized(initialPath), allowSelfSigned: allowSelfSigned, connectionsPerDownload: connections)
        if let server { result.id = server.id }
        return result
    }
    private func test() async { testing = true; result = nil; defer { testing = false }; do { let client = WebDAVClient(server: try configuration(), password: password); defer { client.invalidate() }; let items = try await client.propfind("/", depth: 1); result = "Connected. \(items.count) items in root."; connected = true } catch { result = "Couldn't connect to the server — " + error.localizedDescription; connected = false } }
    private func save() async { saving = true; defer { saving = false }; do { let config = try configuration(); if server == nil { try await registry.add(config, password: password) } else { try await registry.update(config, password: password) }; dismiss() } catch { toast.show(error: error) } }
}
