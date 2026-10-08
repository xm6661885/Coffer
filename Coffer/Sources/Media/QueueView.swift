import SwiftUI

struct QueueView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let current = player.current {
                    HStack {
                        ArtworkView(key: player.metadata[current.id]?.artworkKey, size: 48).clipShape(.rect(cornerRadius: 8))
                        VStack(alignment: .leading) {
                            Text(player.metadata[current.id]?.title ?? current.name).fontWeight(.semibold)
                            if let artist = player.metadata[current.id]?.artist { Text(artist).font(.cofferCaption).foregroundStyle(Color.inkSecondary) }
                        }
                    }.listRowBackground(Color.pinkSoft).contextMenu { FavouriteButton(item: current.fileItem) }
                }
                Section {
                    ForEach(Array(player.queue.enumerated()).filter { $0.offset > player.index }, id: \.offset) { at, ref in
                        Button { player.jump(to: at) } label: { Label(player.metadata[ref.id]?.title ?? PathUtil.baseName(ref.name), systemImage: "music.note").foregroundStyle(Color.ink) }
                            .contextMenu { FavouriteButton(item: ref.fileItem) }
                    }.onDelete { offsets in player.remove(at: IndexSet(offsets.map { $0 + player.index + 1 })) }
                        .onMove { offsets, to in player.move(from: IndexSet(offsets.map { $0 + player.index + 1 }), to: to + player.index + 1) }
                } header: { HStack { Text("Up Next"); Spacer(); Button("Clear") { player.clearUpNext() } } }.listRowBackground(Color.surface)
                Section("History") {
                    ForEach(Array(player.queue.enumerated()).filter { $0.offset < player.index && $0.offset >= player.index - 20 }, id: \.offset) { at, ref in
                        Button { player.jump(to: at) } label: { Text(player.metadata[ref.id]?.title ?? PathUtil.baseName(ref.name)).foregroundStyle(Color.inkSecondary) }
                            .contextMenu { FavouriteButton(item: ref.fileItem) }
                    }
                }.listRowBackground(Color.surface)
            }.environment(\.editMode, .constant(.active)).paperList().navigationTitle("Queue").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button { player.setShuffle(!player.shuffle) } label: { Label("Shuffle", systemImage: "shuffle") }.tint(player.shuffle ? .pinkInk : .inkSecondary) }
                    ToolbarItem(placement: .topBarTrailing) { Button { player.cycleRepeat() } label: { Label("Repeat", systemImage: player.repeatMode == .one ? "repeat.1" : "repeat") }.tint(player.repeatMode == .off ? .inkSecondary : .pinkInk) }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }.presentationDetents([.medium, .large])
    }
}
