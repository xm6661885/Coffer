import SwiftUI

struct FileGridCell: View {
    let item: FileItem
    var selecting = false
    var selected = false
    @Environment(AppSettings.self) private var settings
    var body: some View {
        VStack(spacing: 8) {
            FileIconView(item: item, size: 96).overlay(alignment: .bottomTrailing) {
                if selecting { Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Color.onPink : Color.inkSecondary).background(selected ? Color.pink : Color.clear, in: .circle).contentTransition(.symbolEffect(.replace)).padding(6) }
            }
            MarqueeText(text: settings.showExtensions || item.isDirectory ? item.name : PathUtil.baseName(item.name), style: .caption1)
            Text(item.isDirectory ? Formatters.date(item.modified) : Formatters.bytes(item.size)).font(.cofferCaption).foregroundStyle(Color.inkSecondary)
        }.frame(width: 104).contentShape(Rectangle())
    }
}
