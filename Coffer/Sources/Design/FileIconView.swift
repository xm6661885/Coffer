import SwiftUI

struct FileIconView: View {
    let item: FileItem
    var size: CGFloat = 40
    @Environment(ThumbnailService.self) private var thumbnails
    @Environment(AppSettings.self) private var settings
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    var body: some View {
        RoundedRectangle(cornerRadius: size > 60 ? 14 : 8, style: .continuous)
            .fill(item.isDirectory ? Color.pinkSoft : Color.surfaceSunken)
            .overlay { if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: size, height: size).clipped().clipShape(RoundedRectangle(cornerRadius: size > 60 ? 14 : 8)).overlay { RoundedRectangle(cornerRadius: size > 60 ? 14 : 8).stroke(Color.hairline, lineWidth: 0.5) }.transition(.opacity) } else { Image(systemName: item.kind.symbol).font(.system(size: size * 0.5)).symbolRenderingMode(.hierarchical).foregroundStyle(item.isDirectory ? Color.pinkInk : Color.ink) } }
            .frame(width: size, height: size).accessibilityHidden(true).task(id: item.id + String(item.modified?.timeIntervalSince1970 ?? 0) + "-\(settings.loadVideoThumbnails)-\(settings.loadRemoteThumbnails)") { let result = await thumbnails.thumbnail(for: item, scale: displayScale); withAnimation(.smooth) { image = result } }
    }
}
