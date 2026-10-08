import AVFoundation
import UIKit
import CryptoKit

@MainActor final class MetadataLoader {
    static let artworkRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "Coffer/Artwork")
    func load(_ ref: MediaRef, url: URL?, asset suppliedAsset: AVAsset? = nil) async -> TrackMetadata {
        var result = TrackMetadata(title: PathUtil.baseName(ref.name))
        let localURL = url?.isFileURL == true ? url : nil
        guard suppliedAsset != nil || localURL != nil else { return result }
        var artwork: Data?
        let asset = suppliedAsset ?? AVURLAsset(url: localURL!)
        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                switch item.commonKey { case .commonKeyTitle: result.title = (try? await item.load(.stringValue)) ?? result.title; case .commonKeyArtist: result.artist = try? await item.load(.stringValue); case .commonKeyAlbumName: result.album = try? await item.load(.stringValue); case .commonKeyArtwork: artwork = try? await item.load(.dataValue); default: break }
            }
        }
        if let metadata = try? await asset.load(.metadata), let track = metadata.first(where: { $0.identifier == .id3MetadataTrackNumber || $0.identifier == .iTunesMetadataTrackNumber }) {
            if let number = try? await track.load(.numberValue), number.intValue > 0 { result.trackNumber = number.intValue }
            else if let text = try? await track.load(.stringValue) { result.trackNumber = Int(text.components(separatedBy: "/")[0]) }
            else if let bytes = try? await track.load(.dataValue), bytes.count >= 4 { result.trackNumber = Int(bytes[2]) * 256 + Int(bytes[3]) }
        }
        if let duration = try? await asset.load(.duration), duration.seconds.isFinite { result.duration = duration.seconds }
        if let localURL, result.duration == nil || FileKind.engine(forExt: PathUtil.ext(ref.name)) == .vlc {
            let media = VLCMedia(url: localURL); media.parse(options: VLCMediaParsingOptions(rawValue: 0), timeout: 3000)
            for _ in 0..<30 { if media.parsedStatus.rawValue != 0 { break }; try? await Task.sleep(for: .milliseconds(100)); if Task.isCancelled { media.parseStop(); return result } }
            result.title = media.metaData.title ?? result.title; result.artist = media.metaData.artist ?? result.artist; result.album = media.metaData.album ?? result.album
            if media.metaData.trackNumber > 0 { result.trackNumber = Int(media.metaData.trackNumber) }
            if media.length.intValue > 0 { result.duration = Double(media.length.intValue) / 1000 }
            if artwork == nil, let url = media.metaData.artworkURL, url.isFileURL { artwork = try? await Task.detached { try Data(contentsOf: url, options: .mappedIfSafe) }.value }
        }
        if artwork == nil, let localURL { let directory = localURL.deletingLastPathComponent(); artwork = await Task.detached { for name in ["cover.jpg", "folder.jpg", "front.jpg"] { if let bytes = try? Data(contentsOf: directory.appending(path: name), options: .mappedIfSafe) { return bytes } }; return nil as Data? }.value }
        if let artwork {
            let key = Insecure.SHA1.hash(data: Data(ref.id.utf8)).map { String(format: "%02x", $0) }.joined() + ".jpg"
            let root = Self.artworkRoot
            if await Task.detached(operation: { () -> Bool in
                guard let image = UIImage(data: artwork) else { return false }
                let scale = min(1, 1024 / max(image.size.width, image.size.height)); let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); if let data = resized.jpegData(compressionQuality: 0.85) { try data.write(to: root.appending(path: key), options: .atomic); return true } } catch { return false }; return false
            }).value { result.artworkKey = key }
        }
        return result
    }
}
