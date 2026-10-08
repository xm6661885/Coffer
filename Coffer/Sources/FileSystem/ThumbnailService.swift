import Foundation
import Observation
import UIKit
import QuickLookThumbnailing
import CryptoKit
import AVFoundation

@MainActor @Observable final class ThumbnailService {
    private let memory = NSCache<NSString, UIImage>()
    private var requests: [String: Task<UIImage?, Never>] = [:]
    let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "Coffer/Thumbnails")
    init() { memory.countLimit = 500; memory.totalCostLimit = 64 * 1024 * 1024 }
    func thumbnail(for item: FileItem, scale: CGFloat = 3, size: CGFloat = 80) async -> UIImage? {
        guard [.image, .video, .pdf, .font].contains(item.kind) else { return nil }
        guard item.kind != .video || AppServices.shared.settings.loadVideoThumbnails else { return nil }
        let key = SHA256.hash(data: Data(("v2:" + item.id + ":" + String(item.size ?? 0) + ":" + String(item.modified?.timeIntervalSince1970 ?? 0) + ":" + String(Int(size)) + ":" + (item.etag ?? "")).utf8)).map { String(format: "%02x", $0) }.joined()
        if let image = memory.object(forKey: key as NSString) { return image }
        if let request = requests[key] { return await request.value }
        let disk = directory.appending(path: key + ".jpg")
        let request = Task { () -> UIImage? in
            if let saved = await Task.detached(operation: { UIImage(contentsOfFile: disk.path) }).value { return saved }
            let services = AppServices.shared
            var source: MediaSource?
            let url: URL
            if item.location.isRemote {
                if item.kind == .video {
                    // Use the existing authenticated range stream; close it after extracting one frame.
                    guard services.settings.loadRemoteThumbnails || services.remoteCache.isCached(item) else { return nil }
                    guard let resolved = try? await MediaSourceResolver(registry: services.registry, cache: services.remoteCache, settings: services.settings).resolve(MediaRef(item), preloadOnly: true) else { return nil }
                    source = resolved.0; url = resolved.0.url
                } else {
                    guard services.remoteCache.isCached(item) || (item.kind == .image && (item.size ?? Int64.max) < 5 * 1024 * 1024 && services.settings.loadRemoteThumbnails) else { return nil }
                    guard let cached = try? await services.remoteCache.fetch(item, progress: { _ in }) else { return nil }; url = cached
                }
            } else { url = services.registry.local.url(for: item.path) }
            defer { source?.stream?.close() }
            var result: UIImage?
            if item.kind == .video {
                let asset = AVURLAsset(url: url, options: source.map { ["AVURLAssetHTTPHeaderFieldsKey": $0.headers] })
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: size * scale, height: size * scale)
                generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
                generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
                result = await videoFrame(generator, time: CMTime(seconds: 1, preferredTimescale: 600))
                if result == nil { result = await videoFrame(generator, time: .zero) }
                if result == nil && (source?.headers.isEmpty ?? true) { result = await VLCThumbnailRequest().image(url, size: min(1920, size * scale)) }
            } else {
                let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size), scale: scale, representationTypes: .thumbnail)
                result = await withCheckedContinuation { continuation in QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in continuation.resume(returning: representation?.uiImage) } }
            }
            if let result { await Task.detached { if let data = result.jpegData(compressionQuality: 0.85) { try? FileManager.default.createDirectory(at: disk.deletingLastPathComponent(), withIntermediateDirectories: true); try? data.write(to: disk, options: .atomic) } }.value }
            return result
        }
        requests[key] = request
        let image = await request.value; requests[key] = nil
        if let image { memory.setObject(image, forKey: key as NSString, cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)) }
        return image
    }
    func previewFrame(source: MediaSource, time: Double, duration: Double) async -> UIImage? {
        guard !Task.isCancelled, AppServices.shared.settings.loadVideoThumbnails else { return nil }
        let key = "scrub:" + source.url.absoluteString + ":" + String(Int(time))
        if let saved = memory.object(forKey: key as NSString) { return saved }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source.url, options: ["AVURLAssetHTTPHeaderFieldsKey": source.headers]))
        generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 480, height: 270)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        var result = await videoFrame(generator, time: CMTime(seconds: max(0, time), preferredTimescale: 600))
        if result == nil && !Task.isCancelled && source.headers.isEmpty {
            result = await VLCThumbnailRequest().image(source.url, position: Float(time / max(1, duration)))
        }
        if let result, !Task.isCancelled { memory.setObject(result, forKey: key as NSString, cost: (result.cgImage?.bytesPerRow ?? 0) * (result.cgImage?.height ?? 0)) }
        return Task.isCancelled ? nil : result
    }
    private func videoFrame(_ generator: AVAssetImageGenerator, time: CMTime) async -> UIImage? {
        let deadline = Task { try? await Task.sleep(for: .seconds(8)); guard !Task.isCancelled else { return }; generator.cancelAllCGImageGeneration() }
        defer { deadline.cancel() }
        return await withTaskCancellationHandler {
            guard let frame = try? await generator.image(at: time) else { return nil }
            return UIImage(cgImage: frame.image)
        } onCancel: { generator.cancelAllCGImageGeneration() }
    }
    func clear() async {
        let pending = Array(requests.values); pending.forEach { $0.cancel() }
        for request in pending { _ = await request.value }
        requests.removeAll(); memory.removeAllObjects()
        let directory = directory; await Task.detached { try? FileManager.default.removeItem(at: directory) }.value
    }
}
