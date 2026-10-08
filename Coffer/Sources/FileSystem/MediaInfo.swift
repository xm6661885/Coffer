import Foundation
import AVFoundation
import ImageIO

@MainActor enum MediaInfo {
    static func fields(for item: FileItem, url: URL) async -> [(String, String)] {
        if item.kind == .image {
            return await Task.detached { guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else { return [] }; return [("Dimensions", "\(width) × \(height)")] }.value
        }
        guard item.kind.isMedia else { return [] }
        let asset = AVURLAsset(url: url); var fields: [(String, String)] = []
        if let duration = try? await asset.load(.duration), duration.seconds.isFinite && duration.seconds > 0 { fields.append(("Duration", Formatters.duration(duration.seconds))) }
        let type: AVMediaType = item.kind == .video ? .video : .audio
        if let tracks = try? await asset.loadTracks(withMediaType: type), let track = tracks.first {
            if item.kind == .video, let size = try? await track.load(.naturalSize), let transform = try? await track.load(.preferredTransform) { let size = size.applying(transform); fields.append(("Dimensions", "\(Int(abs(size.width))) × \(Int(abs(size.height)))")) }
            if let descriptions = try? await track.load(.formatDescriptions), let description = descriptions.first { fields.append(("Codec", fourCC(CMFormatDescriptionGetMediaSubType(description)))) }
            if let bitrate = try? await track.load(.estimatedDataRate), bitrate > 0 { fields.append(("Bitrate", "\(Int(bitrate / 1000)) kbps")) }
        } else {
            let media = VLCMedia(url: url); media.parse(options: VLCMediaParsingOptions(rawValue: 0), timeout: 3000)
            for _ in 0..<30 { if media.parsedStatus.rawValue != 0 { break }; try? await Task.sleep(for: .milliseconds(100)); if Task.isCancelled { media.parseStop(); return fields } }
            if fields.isEmpty && media.length.intValue > 0 { fields.append(("Duration", Formatters.duration(Double(media.length.intValue) / 1000))) }
            for raw in media.tracksInformation {
                guard let track = raw as? [String: Any], track[VLCMediaTracksInformationType] as? String == (item.kind == .video ? VLCMediaTracksInformationTypeVideo : VLCMediaTracksInformationTypeAudio) else { continue }
                if let width = track[VLCMediaTracksInformationVideoWidth] as? NSNumber, let height = track[VLCMediaTracksInformationVideoHeight] as? NSNumber { fields.append(("Dimensions", "\(width.intValue) × \(height.intValue)")) }
                if let codec = track[VLCMediaTracksInformationCodec] as? NSNumber { fields.append(("Codec", fourCC(codec.uint32Value))) }
                if let bitrate = track[VLCMediaTracksInformationBitrate] as? NSNumber, bitrate.intValue > 0 { fields.append(("Bitrate", "\(bitrate.intValue / 1000) kbps")) }
                break
            }
        }
        return fields
    }
    static func fourCC(_ value: UInt32) -> String {
        let bytes = [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]
        let raw = String(bytes: bytes, encoding: .ascii) ?? "Unknown"
        return ["hvc1": "HEVC", "hev1": "HEVC", "avc1": "H.264", "mp4a": "AAC", "alac": "ALAC", "flac": "FLAC", "lpcm": "PCM"][raw] ?? raw.uppercased()
    }
}
