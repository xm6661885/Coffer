import UIKit

@MainActor final class VLCThumbnailRequest: NSObject, VLCMediaThumbnailerDelegate {
    private var thumbnailer: VLCMediaThumbnailer?
    private var continuation: CheckedContinuation<UIImage?, Never>?
    private var timeout: Task<Void, Never>?
    func image(_ url: URL, position: Float = 0.1, size: CGFloat = 480) async -> UIImage? {
        await withTaskCancellationHandler { await withCheckedContinuation { continuation in
            guard !Task.isCancelled else { continuation.resume(returning: nil); return }
            self.continuation = continuation
            let media = VLCMedia(url: url); let thumbnailer = VLCMediaThumbnailer(media: media, andDelegate: self); self.thumbnailer = thumbnailer; thumbnailer.thumbnailWidth = size; thumbnailer.thumbnailHeight = size * 9 / 16; thumbnailer.snapshotPosition = max(0, min(0.99, position)); thumbnailer.fetchThumbnail()
            timeout = Task { [weak self] in try? await Task.sleep(for: .seconds(10)); guard !Task.isCancelled else { return }; self?.finish(nil) }
        } } onCancel: { Task { @MainActor in self.finish(nil) } }
    }
    private func finish(_ image: UIImage?) { timeout?.cancel(); thumbnailer?.delegate = nil; thumbnailer = nil; let continuation = continuation; self.continuation = nil; continuation?.resume(returning: image) }
    nonisolated func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer) { Task { @MainActor [weak self] in self?.finish(nil) } }
    nonisolated func mediaThumbnailer(_ mediaThumbnailer: VLCMediaThumbnailer, didFinishThumbnail thumbnail: CGImage) { let image = UIImage(cgImage: thumbnail); Task { @MainActor [weak self] in self?.finish(image) } }
}
