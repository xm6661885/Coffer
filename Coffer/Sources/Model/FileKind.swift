import Foundation

enum FileKind: String, Codable, Sendable, CaseIterable {
    case folder, image, video, audio, pdf, markdown, html, code, data, text, office, archive, ebook, font, package, unknown
    static let imageExtensions = "jpg jpeg png heic heif gif webp bmp tiff tif svg ico raw dng cr2 nef arw".split(separator: " ").map(String.init)
    static let videoExtensions = "mp4 m4v mov mkv avi flv wmv webm ts m2ts mts 3gp rm rmvb mpg mpeg vob ogv f4v asf divx".split(separator: " ").map(String.init)
    static let audioExtensions = "mp3 m4a aac wav aiff aif flac alac ogg oga opus wma ape caf amr m4b mka dsf dff wv tta mid midi".split(separator: " ").map(String.init)
    init(ext: String) {
        let ext = ext.lowercased()
        if Self.imageExtensions.contains(ext) { self = .image; return }
        if Self.videoExtensions.contains(ext) { self = .video; return }
        if Self.audioExtensions.contains(ext) { self = .audio; return }
        if "pdf".split(separator: " ").contains(Substring(ext)) { self = .pdf; return }
        if "md markdown mdown mkd".split(separator: " ").contains(Substring(ext)) { self = .markdown; return }
        if "html htm xhtml".split(separator: " ").contains(Substring(ext)) { self = .html; return }
        if "swift js mjs ts tsx jsx py rb go rs java kt kts c h cpp hpp cc m mm cs php sh bash zsh fish ps1 lua pl r sql css scss less vue dart scala hs ex exs clj gradle cmake makefile dockerfile".split(separator: " ").contains(Substring(ext)) { self = .code; return }
        if "json yaml yml toml xml plist csv tsv ini conf cfg env properties log".split(separator: " ").contains(Substring(ext)) { self = .data; return }
        if "txt text srt ass ssa vtt lrc nfo readme license".split(separator: " ").contains(Substring(ext)) { self = .text; return }
        if "doc docx xls xlsx ppt pptx pages numbers key odt ods odp rtf".split(separator: " ").contains(Substring(ext)) { self = .office; return }
        if "zip rar 7z tar gz tgz bz2 xz".split(separator: " ").contains(Substring(ext)) { self = .archive; return }
        if "epub mobi azw3".split(separator: " ").contains(Substring(ext)) { self = .ebook; return }
        if "ttf otf woff woff2".split(separator: " ").contains(Substring(ext)) { self = .font; return }
        if "ipa apk dmg pkg deb".split(separator: " ").contains(Substring(ext)) { self = .package; return }
        self = ext.isEmpty ? .text : .unknown
    }
    var symbol: String {
        switch self {
        case .folder: return "folder.fill"
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .pdf: return "doc.richtext"
        case .markdown: return "text.document"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .code: return "curlybraces"
        case .data: return "list.bullet.rectangle"
        case .text: return "doc.plaintext"
        case .office: return "doc.text"
        case .archive: return "archivebox"
        case .ebook: return "book.closed"
        case .font: return "textformat"
        case .package: return "shippingbox"
        case .unknown: return "doc"
        }
    }
    var isTextual: Bool { [.markdown, .html, .code, .data, .text].contains(self) }
    var isMedia: Bool { self == .audio || self == .video }
    static func engine(forExt ext: String) -> PlaybackEngine { "mp3 m4a m4b aac wav aiff aif caf flac alac mp4 m4v mov 3gp amr".split(separator: " ").contains(Substring(ext.lowercased())) ? .avfoundation : .vlc }
}
enum PlaybackEngine { case avfoundation, vlc }
