import SwiftUI

enum FileAction: String { case open, playNext, addQueue, addPlaylist, edit, copy, cut, duplicate, move, rename, share, export, compress, uncompress, download, offline, info, delete, playAll }
struct FileContextMenu: View {
    let item: FileItem
    var cached = false
    let perform: (FileAction) -> Void
    var body: some View {
        Section {
            FavouriteButton(item: item)
            if item.kind == .video { VideoThumbnailButton(item: item) }
            action(item.kind.isMedia ? "Play" : "Open", symbol: item.kind == .video ? "play.rectangle" : item.kind == .audio ? "play" : "arrow.up.forward.app", .open)
            if item.kind == .audio { action("Play Next", symbol: "text.line.first.and.arrowtriangle.forward", .playNext); action("Add to Queue", symbol: "text.append", .addQueue) }
            if item.kind.isMedia { action("Add to Playlist…", symbol: "music.note.list", .addPlaylist) }
            if item.kind.isTextual { action("Edit", symbol: "pencil", .edit) }
        }
        Section {
            action("Copy", symbol: "doc.on.doc", .copy); action("Cut", symbol: "scissors", .cut)
            action("Duplicate", symbol: "plus.square.on.square", .duplicate); action("Move…", symbol: "folder", .move); action("Rename", symbol: "pencil.line", .rename)
        }
        Section {
            if !item.isDirectory { action("Share", symbol: "square.and.arrow.up", .share) }
            if item.location == .local { action("Compress", symbol: "archivebox", .compress) }
            if item.ext == "zip" { action("Uncompress", symbol: "archivebox.fill", .uncompress) }
            if item.location.isRemote { action("Download to My iPhone", symbol: "arrow.down.circle", .download); if !item.isDirectory { action(cached ? "Remove Download" : "Make Available Offline", symbol: "arrow.down.circle.fill", .offline) } }
            if item.isDirectory { action("Play All", symbol: "play", .playAll) }
            action("Get Info", symbol: "info.circle", .info)
        }
        Section { Button(role: .destructive) { perform(.delete) } label: { Label("Delete", systemImage: "trash") } }
    }
    private func action(_ title: String, symbol: String, _ action: FileAction) -> some View { Button { perform(action) } label: { Label(title, systemImage: symbol) } }
}
