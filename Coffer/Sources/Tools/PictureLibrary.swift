import Observation

@MainActor @Observable final class PictureLibrary {
    let index = MediaLibraryIndex(kind: .image)
    var entries: [MediaIndexEntry] { index.entries }
    var isScanning: Bool { index.isScanning }
    func load() async { await index.load() }
    func scan(force: Bool = false) async { await index.scan(force: force) }
}
