import SwiftUI

enum MediaLayout: String, CaseIterable { case list = "List", grid = "Grid" }
struct MediaLayoutPicker: View {
    @Binding var layout: MediaLayout
    var body: some View {
        Menu {
            Picker("View", selection: $layout) {
                Label("List", systemImage: "list.bullet").tag(MediaLayout.list)
                Label("Grid", systemImage: "square.grid.2x2").tag(MediaLayout.grid)
            }
        } label: { Label("View", systemImage: layout == .list ? "list.bullet" : "square.grid.2x2") }
            .accessibilityLabel("View layout")
    }
}
