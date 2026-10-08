import Foundation
import Darwin

@MainActor final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    func start(_ url: URL, onChange: @escaping @MainActor () -> Void) {
        cancel()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        source.setEventHandler { [weak self] in
            self?.pending?.cancel()
            let item = DispatchWorkItem { onChange() }
            self?.pending = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
        }
        source.setCancelHandler { close(fd) }
        self.source = source; source.resume()
    }
    func cancel() { pending?.cancel(); pending = nil; source?.cancel(); source = nil }
    deinit { source?.cancel() }
}
