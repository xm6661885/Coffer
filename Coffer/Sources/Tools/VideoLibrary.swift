import Observation
@MainActor @Observable final class VideoLibrary {
    let index = MediaLibraryIndex(kind: .video)
    var entries: [MediaIndexEntry] { index.entries }; var isScanning: Bool { index.isScanning }
    func load() async { await index.load() }
    func scan(force: Bool = false) async { await index.scan(force: force) }
}
