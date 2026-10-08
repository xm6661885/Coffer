import SwiftUI

struct DownloadingView: View {
    let item: FileItem
    let progress: Double
    let cancel: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            FileIconView(item: item, size: 64)
            Text(item.name).font(.cofferHeadline).foregroundStyle(Color.ink).lineLimit(2)
            ProgressBar(value: progress).frame(width: 220)
            Text(progress < 0 ? "Downloading…" : "\(Formatters.bytes(Int64(Double(item.size ?? 0) * progress))) of \(Formatters.bytes(item.size))").font(.cofferTimecode).foregroundStyle(Color.inkSecondary)
            Button("Cancel", action: cancel).buttonStyle(.glass)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.canvas)
    }
}
