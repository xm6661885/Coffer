import SwiftUI

struct FileRow: View {
    let item: FileItem
    var showParent = false
    @Environment(TransferManager.self) private var transfers
    @Environment(AppSettings.self) private var settings
    @Environment(Clipboard.self) private var clipboard
    @State private var count: Int?
    var body: some View {
        HStack(spacing: 12) {
            FileIconView(item: item)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) { MarqueeText(text: settings.showExtensions || item.isDirectory ? item.name : PathUtil.baseName(item.name)); if item.location.isRemote && AppServices.shared.remoteCache.isCached(item) { Image(systemName: "arrow.down.circle.fill").font(.system(size: 10)).foregroundStyle(Color.inkTertiary) } }
                if let task = transfers.task(forDest: item.location, path: item.path) { ProgressBar(value: transfers.progress(for: task.id), height: 3); Text("\(Int(max(0, transfers.progress(for: task.id)) * 100))%").font(.cofferCaption).contentTransition(.numericText()).foregroundStyle(Color.inkSecondary) }
                if transfers.task(forDest: item.location, path: item.path) == nil { Text(subtitle).font(.cofferCaption).foregroundStyle(Color.inkSecondary).monospacedDigit().lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
            if AppServices.shared.player.current?.id == item.id { Image(systemName: "waveform").foregroundStyle(Color.pinkInk).symbolEffect(.variableColor, isActive: AppServices.shared.player.isPlaying).accessibilityLabel("Now playing") }
            if item.isDirectory { Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.inkTertiary) }
        }.frame(minHeight: 56).contentShape(Rectangle())
            .opacity(clipboard.mode == .cut && clipboard.items.contains(item) ? 0.5 : 1)
            .task(id: item.id) { if item.isDirectory && item.location == .local { count = try? await AppServices.shared.registry.local.list(item.path).count } }
    }
    private var subtitle: String {
        if showParent { return item.parentPath }
        if item.isDirectory { return (count.map { "\($0) items · " } ?? "") + Formatters.date(item.modified) }
        return Formatters.bytes(item.size) + " · " + Formatters.date(item.modified)
    }
}
