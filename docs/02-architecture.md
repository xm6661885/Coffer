# 02 · 架构与源码结构

## 1. 目录（必须严格按此创建，文件名一致）
```
Coffer/Sources/
├── App/
│   ├── CofferApp.swift            @main，注入服务，处理 onOpenURL，外观
│   ├── AppDelegate.swift          UIApplicationDelegateAdaptor：方向锁、音频会话初始化
│   ├── RootView.swift             TabView（Files / Tools）+ 迷你播放器 accessory + Toast + 冲突对话框
│   └── AppServices.swift          所有单例服务的创建与持有
├── Design/
│   ├── Theme.swift                Color/Font token（见 01 文档）
│   ├── Components.swift           ProgressBar、GlassIconButton、SectionHeader、EmptyState、Toast 视图
│   └── FileIconView.swift         文件图标/缩略图方块
├── Model/
│   ├── LocationID.swift
│   ├── FileItem.swift
│   ├── FileKind.swift             扩展名 → 类型、SF Symbol、播放后端
│   ├── PathUtil.swift             路径拼接/父目录/唯一名
│   └── Formatters.swift           字节、日期、时长格式化
├── Storage/
│   ├── JSONStore.swift            通用 Codable JSON 持久化（Application Support/Coffer/）
│   ├── Keychain.swift             WebDAV 密码读写
│   ├── AppSettings.swift          所有用户设置（@Observable + UserDefaults）
│   └── RecentsStore.swift         最近打开文件
├── FileSystem/
│   ├── FileProvider.swift         协议 + FileProviderError
│   ├── LocalFileProvider.swift
│   ├── FileProviderRegistry.swift LocationID → provider；服务器列表
│   ├── FileOperations.swift       复制/移动/删除/粘贴/冲突处理（跨位置走 TransferManager）
│   ├── Clipboard.swift            文件剪贴板（copy / cut）
│   ├── DirectoryWatcher.swift     监听本地目录变化（Files App 改动后刷新）
│   ├── ImportService.swift        处理分享菜单/打开方式/文件导入/照片导入
│   ├── ThumbnailService.swift     缩略图生成与缓存
│   └── ZipService.swift           压缩/解压（ZIPFoundation）
├── WebDAV/
│   ├── WebDAVServer.swift         服务器配置模型
│   ├── WebDAVClient.swift         HTTP 方法实现 + 认证 + 证书
│   ├── PropfindParser.swift       XMLParser 解析 multistatus
│   ├── WebDAVFileProvider.swift   FileProvider 实现 + 目录缓存
│   └── RemoteCache.swift          远程文件本地缓存（预览/编辑用）
├── Transfers/
│   ├── TransferTask.swift         任务模型（Codable）
│   ├── TransferManager.swift      队列、并发、重试、网络监听、持久化
│   ├── SegmentedDownloader.swift  多连接分段 + 断点续传下载
│   ├── Uploader.swift             PUT 上传（临时名 + MOVE）
│   └── TransfersView.swift        传输面板
├── Browser/
│   ├── HomeView.swift             首页：My iPhone + WebDAV 服务器
│   ├── AddServerView.swift        添加/编辑服务器
│   ├── BrowserView.swift          文件夹浏览（列表/网格/选择模式/工具栏）
│   ├── BrowserModel.swift         单个文件夹的状态
│   ├── FileRow.swift              列表行
│   ├── FileGridCell.swift         网格单元
│   ├── FileContextMenu.swift      长按菜单内容（列表与网格共用）
│   ├── RenameSheet.swift
│   ├── NewItemSheet.swift         新建文件夹 / 新建文本文件
│   ├── InfoSheet.swift            文件详情
│   ├── DestinationPicker.swift    选择目标文件夹（Move… / Copy to… / Download to… / Upload to…）
│   └── PasteBar.swift             剪贴板非空时底部浮动粘贴条
├── Preview/
│   ├── PreviewRouter.swift        按 FileKind 选择预览视图；远程文件先下载到缓存
│   ├── DownloadingView.swift      远程文件下载进度占位
│   ├── TextPreview.swift          文本/代码/数据：Rendered/Source 切换
│   ├── WebRenderView.swift        WKWebView 包装（markdown/html/高亮/CSV 表格）
│   ├── TextDecoding.swift         编码检测
│   ├── ImagePreview.swift         可缩放图片 + 左右翻页
│   ├── PDFPreview.swift
│   ├── QuickLookPreview.swift
│   ├── ArchivePreview.swift
│   ├── FontPreview.swift
│   └── UnsupportedPreview.swift
├── Media/
│   ├── MediaRef.swift             播放项引用（位置+路径+名称）
│   ├── PlayerBackend.swift        协议：AVPlayerBackend / VLCBackend
│   ├── AVPlayerBackend.swift
│   ├── VLCBackend.swift
│   ├── MediaSourceResolver.swift  MediaRef → 可播放 URL + HTTP 头 / VLC 选项
│   ├── AudioPlayer.swift          全局音乐播放控制器（队列、循环、随机、倍速、睡眠定时）
│   ├── NowPlayingCenter.swift     锁屏/控制中心信息与远程命令
│   ├── MetadataLoader.swift       标题/艺术家/专辑/封面/时长
│   ├── MiniPlayerView.swift       Tab 栏上方 accessory
│   ├── MusicPlayerView.swift      全屏音乐播放器
│   ├── QueueView.swift            播放队列
│   ├── Scrubber.swift             进度条（音乐与视频共用）
│   ├── VideoPlayerModel.swift
│   ├── VideoPlayerView.swift      全屏视频播放器 + 手势
│   ├── VideoSurface.swift         AVPlayerLayer / VLC drawable 的 UIViewRepresentable
│   ├── PiPController.swift
│   ├── OrientationController.swift
│   ├── SystemVolume.swift         MPVolumeView 滑块控制音量
│   ├── SubtitleParser.swift       SRT/VTT 解析（AV 后端外挂字幕）
│   └── PlaybackPositionStore.swift 续播位置
├── Tools/
│   ├── ToolsView.swift
│   ├── TextEditorHome.swift       文本编辑器入口（新建/最近/打开）
│   ├── TextEditorView.swift       编辑器
│   ├── CodeTextView.swift         UITextView 包装
│   ├── MusicLibrary.swift         本地音频扫描与索引
│   ├── MusicLibraryView.swift
│   ├── VideoLibrary.swift
│   ├── VideoLibraryView.swift
│   ├── Playlist.swift             模型 + PlaylistStore
│   ├── PlaylistDetailView.swift
│   └── AddToPlaylistSheet.swift
├── Settings/
│   ├── SettingsView.swift
│   └── LicensesView.swift
└── Support/
    └── Coffer-Bridging-Header.h   （已存在）
```
XcodeGen 会自动收录 `Coffer/Sources` 下的所有 `.swift`，新增文件不需要改 project.yml。

## 2. 并发与状态约定
- 所有 UI 状态类：`@MainActor @Observable final class`。
- 服务单例在 `AppServices` 里创建一次，在 `CofferApp` 用 `.environment(services.xxx)` 注入；视图用 `@Environment(AudioPlayer.self) private var player` 读取。不要使用全局 `static let shared`（`AppServices.shared` 除外，用于非视图代码访问，例如 AppDelegate、NowPlayingCenter 回调）。
- 网络与磁盘 IO 在 `async` 函数中进行，`FileProvider` 实现类不标 `@MainActor`（标 `final class ... : @unchecked Sendable`）。
- 所有 `Task {}` 在视图里用 `.task {}` 或 `.task(id:)`，让 SwiftUI 管理取消。
- 错误：统一 `throw FileProviderError`，UI 层 `catch` 后调用 `services.toast.show(error:)`。

## 3. 核心类型（照抄签名，可补充实现）

### LocationID.swift
```swift
enum LocationID: Hashable, Codable, Sendable {
    case local
    case webdav(UUID)

    var key: String {               // 用于缓存目录名、字典 key
        switch self {
        case .local: return "local"
        case .webdav(let id): return "dav-" + id.uuidString
        }
    }
    var isRemote: Bool { if case .webdav = self { return true } else { return false } }
}
```

### FileItem.swift
```swift
struct FileItem: Identifiable, Hashable, Codable, Sendable {
    let location: LocationID
    let path: String          // 以 "/" 开头，相对于位置根目录；根目录本身是 "/"；目录不以 "/" 结尾（根除外）
    let name: String          // 含扩展名
    let isDirectory: Bool
    let size: Int64?          // 目录为 nil
    let modified: Date?
    let created: Date?
    let etag: String?         // 本地为 nil
    let contentType: String?  // 本地为 nil

    var id: String { location.key + ":" + path }
    var ext: String { isDirectory ? "" : PathUtil.ext(name) }       // 小写，不含点
    var kind: FileKind { isDirectory ? .folder : FileKind(ext: ext) }
    var isHidden: Bool { name.hasPrefix(".") }
    var parentPath: String { PathUtil.parent(path) }
}
```

### PathUtil.swift（全部是纯函数，需写单元级自测思路：根目录、多级、带空格、中文名）
```swift
enum PathUtil {
    static func join(_ dir: String, _ name: String) -> String   // join("/", "a") = "/a"; join("/a", "b") = "/a/b"
    static func parent(_ path: String) -> String                // parent("/a/b") = "/a"; parent("/a") = "/"; parent("/") = "/"
    static func name(_ path: String) -> String                  // 最后一段；"/" → ""
    static func ext(_ name: String) -> String                   // "a.tar.gz" → "gz"; ".bashrc" → ""; "Makefile" → ""
    static func baseName(_ name: String) -> String              // 去掉最后一个扩展名；".bashrc" → ".bashrc"
    static func components(_ path: String) -> [String]          // "/a/b" → ["a","b"]
    static func isAncestor(_ a: String, of b: String) -> Bool   // a == b 或 b 以 a + "/" 开头；a == "/" 时恒 true
    /// 在 existing 中找不冲突的名字："Report.pdf" → "Report 2.pdf" → "Report 3.pdf"；目录同理 "Folder 2"
    static func uniqueName(_ name: String, existing: Set<String>, isDirectory: Bool) -> String
    static func isValidName(_ name: String) -> Bool             // 非空、不含 "/"、不是 "." 或 ".."、去首尾空白后非空、长度 ≤ 255 字节
}
```

### FileKind.swift
```swift
enum FileKind: String, Codable, Sendable {
    case folder, image, video, audio, pdf, markdown, html, code, data, text, office, archive, ebook, font, package, unknown
    init(ext: String)            // 按 01 文档表格映射
    var symbol: String           // SF Symbol 名，按 01 文档表格
    var isTextual: Bool          // markdown, html, code, data, text
    var isMedia: Bool            // audio, video
}

enum PlaybackEngine { case avfoundation, vlc }
extension FileKind {
    /// AVFoundation 能播的扩展名用 .avfoundation，其余用 .vlc
    static func engine(forExt ext: String) -> PlaybackEngine
}
```
AVFoundation 扩展名集合（其余音视频都走 VLC）：
`mp3 m4a m4b aac wav aiff aif caf flac alac mp4 m4v mov 3gp amr`
注意：`webm mkv avi flv wmv ts rmvb ogg opus ape wma` 等一律 VLC。若 AVPlayer 后端播放失败（item.status == .failed），自动用 VLC 后端重试一次。

### FileProvider.swift
```swift
enum FileProviderError: LocalizedError {
    case notFound(String)
    case alreadyExists(String)
    case invalidName
    case unauthorized              // 401
    case forbidden                 // 403
    case insufficientStorage       // 507 或本地磁盘满
    case conflict(String)          // 409 等
    case http(Int)
    case network(Error)
    case cancelled
    case other(String)
    var errorDescription: String? // 英文，见下
}
```
文案：notFound → `"\(name) no longer exists."`；alreadyExists → `"An item named \"\(name)\" already exists."`；invalidName → `"That name isn't allowed."`；unauthorized → `"Wrong username or password."`；forbidden → `"You don't have permission to do that."`；insufficientStorage → `"Not enough storage."`；http(code) → `"The server returned an error (\(code))."`；network(e) → `e.localizedDescription`。

```swift
protocol FileProvider: AnyObject, Sendable {
    var location: LocationID { get }
    func list(_ dirPath: String) async throws -> [FileItem]               // 不含 "." ".."；包含隐藏文件（是否显示由 UI 过滤）
    func stat(_ path: String) async throws -> FileItem
    func createFolder(named name: String, in dirPath: String) async throws -> FileItem
    func createFile(named name: String, in dirPath: String, data: Data) async throws -> FileItem
    func rename(_ item: FileItem, to newName: String) async throws -> FileItem
    func delete(_ item: FileItem) async throws
    /// 同一位置内复制/移动。目标已存在且 overwrite == false 时 throw .alreadyExists
    func copy(_ item: FileItem, toDir: String, newName: String, overwrite: Bool) async throws
    func move(_ item: FileItem, toDir: String, newName: String, overwrite: Bool) async throws
}
```

### JSONStore.swift
```swift
/// 位于 Application Support/Coffer/<fileName>。读取失败返回 defaultValue。写入原子化（.atomic）。
struct JSONStore<Value: Codable> {
    let fileName: String
    func load(default defaultValue: Value) -> Value
    func save(_ value: Value)            // 在后台队列写；调用方负责去抖（需要时 0.5s）
}
```
使用的文件名：`servers.json`、`transfers.json`、`playlists.json`、`positions.json`、`recents.json`、`music-index.json`、`video-index.json`、`dir-cache-<locationKey>.json`。

### AppServices.swift
```swift
@MainActor
final class AppServices {
    static let shared = AppServices()
    let settings = AppSettings()
    let registry: FileProviderRegistry
    let transfers: TransferManager
    let operations: FileOperations
    let clipboard = Clipboard()
    let toast = ToastCenter()
    let thumbnails = ThumbnailService()
    let remoteCache: RemoteCache
    let player: AudioPlayer          // 音乐
    let playlists = PlaylistStore()
    let music: MusicLibrary
    let videos: VideoLibrary
    let positions = PlaybackPositionStore()
    let recents = RecentsStore()
    let importer: ImportService
    let orientation = OrientationController()
    // init 中按依赖顺序创建
}
```
`CofferApp` 里把以上每个 `@Observable` 对象用 `.environment(...)` 注入到 `RootView`。

### ToastCenter（放在 Components.swift）
```swift
@MainActor @Observable final class ToastCenter {
    struct Toast: Identifiable, Equatable { let id = UUID(); let message: String; let symbol: String?; let actionTitle: String?; let action: (() -> Void)?; static func == ... id 比较 }
    private(set) var current: Toast?
    func show(_ message: String, symbol: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil)  // 2.5s 后自动消失；有 action 时 4s
    func show(error: Error)          // symbol "exclamationmark.triangle"
}
```
Toast 视图：在 RootView 最顶层 `.overlay(alignment: .top)`，安全区顶部下方 8pt，胶囊，`.glassEffect(.regular, in: .capsule)`，内边距 水平 16 垂直 10，HStack(symbol, message, 可选 action 按钮 `.pinkInk` 字重 semibold)。出现：`.transition(.move(edge: .top).combined(with: .opacity))` + `.smooth`。向上轻扫可关闭。

## 4. 依赖使用要点
- MobileVLCKit：通过 bridging header 暴露，Swift 中直接使用 `VLCMediaPlayer`、`VLCMedia`，**不要**写 `import MobileVLCKit`。
- ZIPFoundation：`import ZIPFoundation`，用 `FileManager.zipItem(at:to:)`、`FileManager.unzipItem(at:to:)` 和 `Archive(url:accessMode:)` 列条目。
- Web 资源：`Bundle.main.url(forResource: "marked.umd", withExtension: "js")` 等，XcodeGen 已将 `Coffer/Resources/Web` 下文件作为资源打包（扁平放在 bundle 根目录）。
