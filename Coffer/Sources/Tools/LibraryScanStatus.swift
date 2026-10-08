import SwiftUI

/// Inline scan progress shown at the top of a media library while it re-indexes.
struct LibraryScanStatus: View {
    let index: MediaLibraryIndex
    var body: some View {
        if index.isScanning {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if index.scanProgress == nil { ProgressView().controlSize(.small) }
                    Text(index.scanStatus ?? "Scanning…").font(.cofferCaption).foregroundStyle(Color.inkSecondary).lineLimit(1)
                    Spacer(minLength: 0)
                    if let progress = index.scanProgress { Text(progress, format: .percent.precision(.fractionLength(0))).font(.cofferCaption).monospacedDigit().foregroundStyle(Color.inkSecondary).contentTransition(.numericText()) }
                }
                if let progress = index.scanProgress { ProgressView(value: progress).tint(Color.pink).animation(.linear(duration: 0.2), value: progress) }
            }.frame(maxWidth: .infinity, alignment: .leading).transition(.opacity)
        } else if let error = index.error {
            Label(error, systemImage: "exclamationmark.triangle").font(.cofferCaption).foregroundStyle(Color.danger).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Toolbar button that forces a full re-scan, bypassing cached remote listings.
struct LibraryRefreshButton: View {
    let index: MediaLibraryIndex
    var body: some View {
        Button { Task { await index.scan(force: true) } } label: { Label("Refresh Library", systemImage: "arrow.clockwise") }
            .disabled(index.isScanning).accessibilityLabel("Refresh Library")
    }
}
