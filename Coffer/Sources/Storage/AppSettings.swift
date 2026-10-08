import SwiftUI
import Observation

enum ThemeChoice: String, CaseIterable, Codable { case system = "System", light = "Light", dark = "Dark"; var colorScheme: ColorScheme? { switch self { case .system: return nil; case .light: return .light; case .dark: return .dark } } }
enum ViewMode: String, CaseIterable, Codable { case list = "List", grid = "Icons" }
enum SortKey: String, CaseIterable, Codable { case name = "Name", date = "Date", size = "Size", kind = "Kind" }
@MainActor @Observable final class AppSettings {
    var theme: ThemeChoice { didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") } }
    var viewMode: ViewMode { didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode") } }
    var sortKey: SortKey { didSet { UserDefaults.standard.set(sortKey.rawValue, forKey: "sortKey") } }
    var showHiddenFiles: Bool { didSet { UserDefaults.standard.set(showHiddenFiles, forKey: "showHiddenFiles") } }
    var showExtensions: Bool { didSet { UserDefaults.standard.set(showExtensions, forKey: "showExtensions") } }
    var foldersOnTop: Bool { didSet { UserDefaults.standard.set(foldersOnTop, forKey: "foldersOnTop") } }
    var tapAudioOpensPlayer: Bool { didSet { UserDefaults.standard.set(tapAudioOpensPlayer, forKey: "tapAudioOpensPlayer") } }
    var skipInterval: Int { didSet { UserDefaults.standard.set(skipInterval, forKey: "skipInterval") } }
    var longPressSpeed: Double { didSet { UserDefaults.standard.set(longPressSpeed, forKey: "longPressSpeed") } }
    var autoRotateVideo: Bool { didSet { UserDefaults.standard.set(autoRotateVideo, forKey: "autoRotateVideo") } }
    var autoPiP: Bool { didSet { UserDefaults.standard.set(autoPiP, forKey: "autoPiP") } }
    var backgroundVideoAudio: Bool { didSet { UserDefaults.standard.set(backgroundVideoAudio, forKey: "backgroundVideoAudio") } }
    var resumePlayback: Bool { didSet { UserDefaults.standard.set(resumePlayback, forKey: "resumePlayback") } }
    var streamRemoteMedia: Bool { didSet { UserDefaults.standard.set(streamRemoteMedia, forKey: "streamRemoteMedia") } }
    var preloadNextVideo: Bool { didSet { UserDefaults.standard.set(preloadNextVideo, forKey: "preloadNextVideo") } }
    var loadRemoteThumbnails: Bool { didSet { UserDefaults.standard.set(loadRemoteThumbnails, forKey: "loadRemoteThumbnails") } }
    var maxConcurrentTransfers: Int { didSet { UserDefaults.standard.set(maxConcurrentTransfers, forKey: "maxConcurrentTransfers") } }
    var wifiOnly: Bool { didSet { UserDefaults.standard.set(wifiOnly, forKey: "wifiOnly") } }
    var cacheLimit: Int64 { didSet { UserDefaults.standard.set(cacheLimit, forKey: "cacheLimit") } }
    var lastImportDestination: String { didSet { UserDefaults.standard.set(lastImportDestination, forKey: "lastImportDestination") } }
    var wrapLines: Bool { didSet { UserDefaults.standard.set(wrapLines, forKey: "wrapLines") } }
    var lineNumbers: Bool { didSet { UserDefaults.standard.set(lineNumbers, forKey: "lineNumbers") } }
    var previewTextSize: Int = UserDefaults.standard.object(forKey: "previewTextSize") as? Int ?? 13 { didSet { UserDefaults.standard.set(previewTextSize, forKey: "previewTextSize") } }
    var textSize: Int { didSet { UserDefaults.standard.set(textSize, forKey: "textSize") } }
    var sortAscending: Bool { didSet { UserDefaults.standard.set(sortAscending, forKey: "sortAscending") } }
    var musicSources: [BrowserRoute] { didSet { UserDefaults.standard.set(try? JSONEncoder().encode(musicSources), forKey: "musicSources") } }
    var showRecents = UserDefaults.standard.object(forKey: "showRecents") as? Bool ?? true { didSet { UserDefaults.standard.set(showRecents, forKey: "showRecents") } }
    var pictureSources = (UserDefaults.standard.data(forKey: "pictureSources").flatMap { try? JSONDecoder().decode([BrowserRoute].self, from: $0) }) ?? [] { didSet { UserDefaults.standard.set(try? JSONEncoder().encode(pictureSources), forKey: "pictureSources") } }
    var loadVideoThumbnails = UserDefaults.standard.object(forKey: "loadVideoThumbnails") as? Bool ?? true { didSet { UserDefaults.standard.set(loadVideoThumbnails, forKey: "loadVideoThumbnails") } }
    var videoSources: [BrowserRoute] { didSet { UserDefaults.standard.set(try? JSONEncoder().encode(videoSources), forKey: "videoSources") } }
    init() {
        let d = UserDefaults.standard
        theme = ThemeChoice(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        viewMode = ViewMode(rawValue: d.string(forKey: "viewMode") ?? "") ?? .list
        sortKey = SortKey(rawValue: d.string(forKey: "sortKey") ?? "") ?? .name
        showHiddenFiles = (d.object(forKey: "showHiddenFiles") as? Bool) ?? false
        showExtensions = (d.object(forKey: "showExtensions") as? Bool) ?? true
        foldersOnTop = (d.object(forKey: "foldersOnTop") as? Bool) ?? true
        tapAudioOpensPlayer = (d.object(forKey: "tapAudioOpensPlayer") as? Bool) ?? false
        skipInterval = (d.object(forKey: "skipInterval") as? Int) ?? 10
        longPressSpeed = (d.object(forKey: "longPressSpeed") as? Double) ?? 2
        autoRotateVideo = false
        autoPiP = (d.object(forKey: "autoPiP") as? Bool) ?? true
        backgroundVideoAudio = (d.object(forKey: "backgroundVideoAudio") as? Bool) ?? true
        resumePlayback = (d.object(forKey: "resumePlayback") as? Bool) ?? true
        streamRemoteMedia = (d.object(forKey: "streamRemoteMedia") as? Bool) ?? true
        preloadNextVideo = (d.object(forKey: "preloadNextVideo") as? Bool) ?? true
        loadRemoteThumbnails = (d.object(forKey: "loadRemoteThumbnails") as? Bool) ?? true
        maxConcurrentTransfers = (d.object(forKey: "maxConcurrentTransfers") as? Int) ?? 3
        wifiOnly = (d.object(forKey: "wifiOnly") as? Bool) ?? false
        cacheLimit = (d.object(forKey: "cacheLimit") as? NSNumber)?.int64Value ?? 2_000_000_000
        lastImportDestination = (d.object(forKey: "lastImportDestination") as? String) ?? "/"
        wrapLines = (d.object(forKey: "wrapLines") as? Bool) ?? true
        lineNumbers = (d.object(forKey: "lineNumbers") as? Bool) ?? true
        textSize = (d.object(forKey: "textSize") as? Int) ?? 13
        sortAscending = (d.object(forKey: "sortAscending") as? Bool) ?? true
        musicSources = (d.data(forKey: "musicSources").flatMap { try? JSONDecoder().decode([BrowserRoute].self, from: $0) }) ?? []
        videoSources = (d.data(forKey: "videoSources").flatMap { try? JSONDecoder().decode([BrowserRoute].self, from: $0) }) ?? []
    }
}
