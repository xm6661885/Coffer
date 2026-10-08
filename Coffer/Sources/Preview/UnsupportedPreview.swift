import SwiftUI

struct UnsupportedPreview: View {
    let item: FileItem
    let url: URL
    @State private var asText = false
    @State private var share = false
    var body: some View {
        Group {
            if asText { TextPreview(item: item, url: url, mode: .plain) }
            else { ContentUnavailableView { Label("No preview available", systemImage: item.kind.symbol) } description: { Text("\(item.kind.rawValue.capitalized) · \(Formatters.bytes(item.size))") } actions: {
                Button { share = true } label: { Text("Open in…").foregroundStyle(Color.onPink) }.buttonStyle(.glassProminent).tint(.pink)
                Button("Open as Text") { asText = true }.buttonStyle(.glass)
            } }
        }.background(Color.canvas).sheet(isPresented: $share) { NavigationStack { DocumentInteractionView(url: url).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { share = false } } } }.presentationBackground(Color.canvas) }
    }
}
