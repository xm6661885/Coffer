# 05 · WebDAV 与传输引擎

目标：WebDAV 位置在 UI 上与本地完全一致（同一个 BrowserView），只是多了“下载/离线”状态；传输稳定（分段并发、断点续传、自动重试、网络恢复自动继续、App 重启后恢复队列）。

## 1. 服务器模型
```swift
struct WebDAVServer: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var baseURL: URL              // 例如 https://nas.local:5006/dav（不以 / 结尾，保存时去掉末尾 /）
    var username: String
    var initialPath: String = "/"
    var allowSelfSigned = false
    var connectionsPerDownload = 4
    var lastError: String?        // 最近一次失败的文案（Codable 持久化，用于首页 Offline 标记）
}
```
密码：`Keychain.set(password, account: server.id.uuidString)`，service = `app.coffer.webdav`，`kSecAttrAccessibleAfterFirstUnlock`。删除服务器时一并删除 Keychain 项、`dir-cache-<key>.json`、`Caches/Coffer/Remote/<key>/`。

`FileProviderRegistry`（@MainActor @Observable）：持有 `servers: [WebDAVServer]`（servers.json），`provider(for: LocationID) -> FileProvider`（WebDAVFileProvider 实例按 id 缓存），`add/update/remove/move`，`displayName(for: LocationID)`。

## 2. URL 规则（最容易出错，必须严格遵守）
- 内部路径（FileItem.path）始终是**未编码**的人类可读路径，例如 `/Music/Café Del Mar/01 Intro.mp3`。
- 拼请求 URL：`func url(for path: String, isDirectory: Bool) -> URL`
  1. 把 path 拆成 components，每段用 `addingPercentEncoding(withAllowedCharacters: .webdavSegment)` 编码，其中 `.webdavSegment = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#[]@!$&'()*+,;="))`。
  2. `baseURL.absoluteString + "/" + encodedComponents.joined("/")`；isDirectory 时末尾加 `/`（根目录就是 `baseURL + "/"`）。
- 解析 PROPFIND 响应中的 `<d:href>`：
  1. href 可能是绝对 URL（`https://host/dav/a%20b/`）或绝对路径（`/dav/a%20b/`）。都先转成 `URL(string:, relativeTo: baseURL)`，取 `.path(percentEncoded: true)`。
  2. 去掉 baseURL 自身的 path 前缀（比较时两边都先 `removingPercentEncoding` 再比较，并统一去掉末尾 `/`）。
  3. 剩下部分 `removingPercentEncoding`，确保以 `/` 开头，去掉末尾 `/` → FileItem.path。
  4. 第一个 response 通常是目录本身：当解析出的 path == 请求的 dirPath 时跳过。
  5. 名称优先用 `<d:displayname>`；若为空或与 path 最后一段解码结果不同（有些服务器 displayname 不可靠），**以 path 最后一段为准**。
- 用户在 AddServerView 里粘贴的 URL 可能包含已编码字符（`%20`），直接 `URL(string:)` 保存即可；不要二次编码 baseURL。

## 3. WebDAVClient
```swift
final class WebDAVClient: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let server: WebDAVServer
    private let password: String
    private lazy var session: URLSession   // 见下
    func propfind(_ path: String, depth: Int) async throws -> [FileItem]
    func mkcol(_ path: String) async throws
    func delete(_ path: String, isDirectory: Bool) async throws
    func move(from: String, to: String, isDirectory: Bool, overwrite: Bool) async throws
    func copy(from: String, to: String, isDirectory: Bool, overwrite: Bool) async throws
    func put(data: Data, to path: String) async throws        // 小文件（新建文本、保存编辑）
    func head(_ path: String) async throws -> (size: Int64?, etag: String?, acceptRanges: Bool, lastModified: Date?)
    func authorizedRequest(_ url: URL, method: String) -> URLRequest
    var authHeader: String                                    // "Basic base64(user:pass)"
}
```
- Session：`URLSessionConfiguration.default`，`timeoutIntervalForRequest = 30`，`timeoutIntervalForResource = 7 * 24 * 3600`，`httpMaximumConnectionsPerHost = 16`，`requestCachePolicy = .reloadIgnoringLocalCacheData`，`urlCache = nil`，`waitsForConnectivity = false`，delegate = self。
- 认证：
  - 每个请求都**预先**带上 `Authorization: Basic ...`（多数 NAS 都支持，避免一次 401 往返）。
  - 实现 `urlSession(_:task:didReceive challenge:)`：`NSURLAuthenticationMethodHTTPDigest` 时返回 `URLCredential(user:, password:, persistence: .forSession)`（支持 Digest）；`NSURLAuthenticationMethodServerTrust` 且 `server.allowSelfSigned` 时 `.useCredential, URLCredential(trust:)`；其它 `.performDefaultHandling`。若 previousFailureCount > 0 则 `.cancelAuthenticationChallenge`（避免死循环）并最终映射为 `.unauthorized`。
- PROPFIND 请求体（固定）：
  ```xml
  <?xml version="1.0" encoding="utf-8"?>
  <d:propfind xmlns:d="DAV:"><d:prop>
    <d:displayname/><d:resourcetype/><d:getcontentlength/><d:getlastmodified/><d:creationdate/><d:getetag/><d:getcontenttype/>
  </d:prop></d:propfind>
  ```
  头：`Depth: 1`，`Content-Type: application/xml; charset=utf-8`。成功状态 207。
- 状态码映射：200/201/204/207 成功；401 → unauthorized；403 → forbidden；404 → notFound；405（MKCOL 已存在）→ alreadyExists；409 → conflict（父目录不存在）；412（Overwrite: F 且存在）→ alreadyExists；423 → other("The file is locked."); 507 → insufficientStorage；其它 → http(code)。
- MOVE/COPY：头 `Destination: <完整编码后的绝对 URL>`，`Overwrite: T` 或 `F`，目录时 COPY 加 `Depth: infinity`。
- DELETE 目录时 URL 末尾带 `/`。

### PropfindParser
基于 `XMLParser`，`shouldProcessNamespaces = true`，按 `elementName`（本地名）匹配，忽略命名空间前缀差异（`D:`、`d:`、`lp1:` 都要支持）。
- 每个 `<response>`：收集 href；`<propstat>` 中只采用 `<status>` 含 ` 200 ` 的 prop。
- `resourcetype` 内出现 `<collection/>` → 目录。
- `getcontentlength` → Int64。
- `getlastmodified` 用 RFC1123 解析：`DateFormatter`，`locale = en_US_POSIX`，`timeZone = GMT`，格式依次尝试 `"EEE, dd MMM yyyy HH:mm:ss zzz"`、`"EEEE, dd-MMM-yy HH:mm:ss zzz"`、`"EEE MMM d HH:mm:ss yyyy"`。
- `creationdate` 用 `ISO8601DateFormatter`（带与不带小数秒两种都试）。
- `getetag` 去掉引号与 `W/` 前缀。

## 4. WebDAVFileProvider
实现 FileProvider：
- `list`：PROPFIND depth 1；成功后写入目录缓存（`DirectoryCache`：内存字典 + `dir-cache-<key>.json`，结构 `[path: CachedListing(items, fetchedAt)]`，最多保留 300 个目录，LRU 淘汰）。另提供 `cachedList(_ path) -> [FileItem]?` 供 BrowserModel 先显示。
- 缓存新鲜度：30 秒内重复进入同一目录不重新请求（除非 `force`）。
- `createFolder` → MKCOL。`createFile` → PUT。`rename` → MOVE 同目录。`delete` → DELETE。`copy/move` → COPY/MOVE（服务端完成，无需下载）。
- 每次写操作成功后，使相关目录缓存失效并发 `.cofferDirectoryChanged`。
- 连接失败时更新 `server.lastError`（registry 负责持久化），成功时清空。

## 5. 远程文件缓存 RemoteCache
用于：预览、文本编辑、分享、播放不支持流式的格式。
```swift
@MainActor @Observable final class RemoteCache {
    func localURL(for item: FileItem) -> URL               // Caches/Coffer/Remote/<key>/<path>
    func isCached(_ item: FileItem) -> Bool                // 文件存在 且 记录的 etag/size/modified 与 item 一致
    func fetch(_ item: FileItem, progress: @escaping (Double) -> Void) async throws -> URL   // 通过 TransferManager 下载（kind = .cache），已缓存则直接返回
    var pinned: Set<String>                                // Make Available Offline 的 item.id（pinned.json 不需要，存在 UserDefaults）
    func pin(_ item: FileItem) / unpin(_ item: FileItem)
    func totalSize() -> Int64
    func clear(keepPinned: Bool)
}
```
- 元信息：同目录下 `.<name>.meta.json`（etag、size、modified）。
- 自动清理：启动时若非 pinned 缓存总量 > `settings.cacheLimit`（默认 2 GB，可选 500 MB / 1 / 2 / 5 / 10 GB / Unlimited），按最后访问时间删除到 80%。
- Make Available Offline = fetch + pin；pin 的文件不被自动清理。

## 6. 传输引擎
### 6.1 模型
```swift
struct TransferTask: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case download, upload, cache }   // cache = 预览用下载，不显示在“Completed”中
    enum State: String, Codable { case queued, running, paused, waitingForNetwork, failed, completed, cancelled }
    var id = UUID()
    var kind: Kind
    var source: FileItem            // 下载：远程项；上传：本地项
    var destLocation: LocationID
    var destPath: String            // 目标完整路径（含文件名）
    var deleteSourceOnSuccess = false   // 跨位置 move
    var totalBytes: Int64
    var completedBytes: Int64
    var state: State = .queued
    var attempts = 0
    var lastError: String?
    var createdAt = Date()
    var finishedAt: Date?
    var etag: String?               // 开始下载时的 etag，用于 If-Range
    var segments: [Segment] = []    // 下载分段
    struct Segment: Codable, Hashable { var index: Int; var start: Int64; var end: Int64; var done: Int64 }  // [start, end] 闭区间
}
```
文件夹传输：在入队时**展开**为目录结构 + 每个文件一个任务（下载：PROPFIND 递归获取全部文件，深度优先，先在本地创建目录；上传：本地 enumerator 递归，先在远端逐级 MKCOL）。另外在 `TransferManager` 中记录 `groups: [UUID: TransferGroup(name, taskIDs)]` 用于 UI 汇总显示一个文件夹任务。

### 6.2 TransferManager
```swift
@MainActor @Observable final class TransferManager {
    private(set) var tasks: [TransferTask]                   // 按 createdAt
    var activeCount: Int; var overallProgress: Double         // 用于首页圆环
    var speed: Double                                         // 所有运行任务合计 bytes/s（每秒刷新，3 秒滑动平均）
    func enqueueDownload(_ item: FileItem, toLocal dirPath: String) async
    func enqueueUpload(_ localItem: FileItem, to location: LocationID, dirPath: String) async
    func enqueueCache(_ item: FileItem) -> UUID
    func pause(_ id: UUID); func resume(_ id: UUID); func cancel(_ id: UUID); func retry(_ id: UUID)
    func pauseAll(); func resumeAll(); func clearFinished()
    func progress(for id: UUID) -> Double
    func task(forDest location: LocationID, path: String) -> TransferTask?   // 文件行显示进度
}
```
调度规则：
- 最多同时运行 `settings.maxConcurrentTransfers`（默认 3，范围 1–6）个任务；`cache` 任务优先插到队首并且不占名额上限（用户正在等预览）。
- 每次状态变化后 `schedule()`：取 queued 中最早的任务启动。
- 持久化：tasks 变化时去抖 1s 写 `transfers.json`（不保存 cache 类任务和已完成超过 7 天的任务）。启动时加载：`running` 状态的任务改为 `queued`（自动续传）。
- 网络监听：`NWPathMonitor`。路径不可用时把 running 任务全部暂停为 `waitingForNetwork`（保留已完成分段）；恢复可用时 2 秒后把 waitingForNetwork 改回 queued 并 schedule。
- `settings.wifiOnly`（默认关）：开启时，蜂窝网络下非 cache 任务保持 waitingForNetwork，UI 显示 `Waiting for Wi-Fi`。
- 后台：进入后台时调用 `UIApplication.shared.beginBackgroundTask(withName: "transfers")` 尽量继续传输，到期回调中把运行中任务标为 queued 并保存（下次打开自动继续）。另外：只要在后台播放音频，App 不会被挂起，传输会持续。**不要**使用 background URLSession（它不支持分段并发与精确进度，复杂度高）。
- 传输完成：toast（仅 download/upload，且不是由于批量产生的第 2 个以后，批量时只在整组完成后 toast 一次：`Downloaded "Album" (24 files)`），触感 success；发 `.cofferDirectoryChanged`。

### 6.3 SegmentedDownloader（多线程 + 断点续传）
```swift
final class SegmentedDownloader: @unchecked Sendable {
    init(task: TransferTask, client: WebDAVClient, partDir: URL, connections: Int,
         onProgress: @escaping @Sendable (_ segments: [TransferTask.Segment]) -> Void)
    func run() async throws -> URL   // 返回合并后的临时文件 URL
    func cancel()
}
```
流程：
1. `HEAD`（若 HEAD 返回 405，改用 `GET` + `Range: bytes=0-0`，从 `Content-Range: bytes 0-0/12345` 取总大小）。得到 size、etag、是否支持 Range（`Accept-Ranges: bytes` 或 206 响应）。
2. 若 task.segments 已存在且 etag 与记录一致（或都为 nil 且 size 一致）→ 续传；否则删除 partDir 内容重新分段。
3. 分段：size < 8 MB 或不支持 Range → 单段；否则段数 = `min(connections, max(1, size / 4MB))`，平均切分。
4. 每段一个 `URLSessionDataTask`（同一个 downloader 专用的 `URLSession`，delegate = 一个内部 `SegmentDelegate: NSObject, URLSessionDataDelegate`，delegateQueue 为串行 OperationQueue）。请求：`GET` + `Range: bytes=\(start + done)-\(end)` + `If-Range: "<etag>"`（有 etag 时）+ Authorization。
   - `didReceive response`：检查状态码（206 正常；200 见下；其它按错误处理）。
   - `didReceive data`：追加到该段的内存缓冲，缓冲 ≥ 256 KB 时用 `FileHandle(forWritingTo: partDir/seg-<index>)` `seekToEnd()` + `write(contentsOf:)` 落盘并更新 `done`。
   - `didCompleteWithError`：先把剩余缓冲落盘，再结束该段（用 `CheckedContinuation` 把回调桥接为 async）。
   - 每 250ms 节流回调一次 onProgress（让 UI 平滑）。
   - 禁止使用 `session.bytes(for:)` 逐字节迭代（CPU 开销太大）。
   - 若带 Range 的请求返回 200（服务器忽略 Range）：该段作废，退回单段整体下载（取消其他段）。
5. 每段失败重试：网络错误/5xx/超时 → 等待 `min(30, 2^attempt) + random(0...1)` 秒后从该段当前 `done` 继续，单段最多 8 次；401/403/404 → 立即失败不重试。
6. 全部完成后按 index 顺序把 seg 文件拼接到 `partDir/merged`（用 FileHandle 分块 4MB 复制），校验总大小 == size，然后返回。
7. TransferManager 把 merged 移动到目标位置（目标存在：冲突处理在入队时已决定，此时直接替换），删除 partDir。

速度与剩余时间：TransferManager 每秒对每个任务记录 completedBytes 差值，3 秒滑动平均；剩余时间 = (total - completed) / speed。

### 6.4 Uploader
WebDAV 不支持标准的断点续传上传，所以策略是：
1. 先确保远端父目录存在（若 409 则逐级 MKCOL）。
2. 上传到临时名：`<dir>/.<name>.coffer-upload`（`uploadTask(with: request, fromFile:)`，PUT，`Content-Length` 自动），用 `URLSessionTaskDelegate.didSendBodyData` 更新进度。
3. 成功后 `MOVE` 临时文件到正式名（`Overwrite: T`）。若服务器不允许 MOVE 到已有文件，先 DELETE 再 MOVE。
4. 失败重试：同下载的退避规则，最多 5 次，每次从头上传（UI 显示 `Retrying (2/5)…`）。
5. 上传完成后 `PROPFIND depth 0` 校验远端大小 == 本地大小，不一致视为失败。
6. 取消时尝试 DELETE 临时文件。

### 6.5 传输面板 TransfersView
从首页菜单 `Transfers`、首页圆环按钮、Toast 的 `View` 动作打开。`.sheet`，`.presentationDetents([.medium, .large])`，`.presentationBackgroundInteraction(.enabled(upThrough: .medium))`。

```
Transfers                                   [ellipsis.circle Menu]   [Done]
  ┌────────────────────────────────────────────────────────────────┐
  │ 3 active · 12.4 MB/s · About 2 min left                        │   ← 汇总行（caption），无活动时隐藏
  └────────────────────────────────────────────────────────────────┘
In Progress
  [icon] Movie.mkv                                        [pause]
         ███████████░░░░░░░░  58%                                  ← ProgressBar 高 6
         1.2 GB of 2.1 GB · 8.3 MB/s · 1:52 left · 4 connections
  [icon] Photos (Folder)                                  [pause]
         ████░░░░░░░░  12 of 120 files
Queued
  [icon] song.flac                                        [xmark]
         Waiting
Failed
  [icon] doc.pdf                                [arrow.clockwise]
         Failed. Tap to retry. — Server returned an error (500)
Completed
  [icon] photo.heic                                [magnifyingglass]   ← 点击：在 Files 中定位（reveal）
         Downloaded to My iPhone › Inbox · 2 min ago
```
- 每行右侧单个圆形图标按钮（`.buttonStyle(.glass)`，`.buttonBorderShape(.circle)`）：运行中 = pause；暂停 = play（`Resume`）；排队 = xmark（cancel）；失败 = arrow.clockwise（retry）；完成 = magnifyingglass（reveal）。
- 左滑：`Cancel`（运行/排队/暂停/失败）或 `Remove`（完成）。
- 第三行（详细信息）：`completed of total · speed · remaining · N connections`。暂停：`Paused · 1.2 GB of 2.1 GB`。等待网络：`Waiting for network`。重试中：`Retrying in 4s (attempt 3 of 8)`。
- 右上 Menu：`Pause All`、`Resume All`、`Clear Completed`、Divider、`Only on Wi-Fi` Toggle（绑定 settings.wifiOnly）。
- 汇总与每行数字使用 `.contentTransition(.numericText())`；进度条宽度变化用 `.animation(.linear(duration: 0.25), value:)`。
- 空状态：`ContentUnavailableView("No transfers", systemImage: "arrow.up.arrow.down", description: Text("Downloads and uploads will appear here."))`。

### 6.6 ProgressBar 组件（Components.swift）
```swift
struct ProgressBar: View {
    var value: Double            // 0...1；传负数（-1）表示进度未知，显示不确定动画（一段 30% 长度的 pink 块左右往返，.linear 1.2s repeatForever）
    var height: CGFloat = 6
    // 轨道 Capsule pinkSoft，进度 Capsule pink，宽度 = 总宽 * value（最小显示宽度 = height，避免 0% 时看不到）
}
```

## 7. 远程媒体流式播放
- AVPlayer：`AVURLAsset(url: remoteURL, options: ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": client.authHeader]])`。这是私有常量名但被广泛使用且稳定；如果编译期需要字符串常量，直接用该字符串。自签名证书场景下 AVPlayer 无法绕过证书校验：此时 `MediaSourceResolver` 改为先完整下载到 RemoteCache 再播放（显示 DownloadingView）。
- VLC：`VLCMedia(url: remoteURL)`；认证：把用户名密码放入 URL（`https://user:pass@host/...`，用户名和密码先 percent-encode），并 `media.addOption(":http-user-agent=Coffer")`。自签名证书同样回退到缓存下载。
- 用户可在设置中关闭 `Stream remote media`（默认开），关闭时一律先下载缓存。
