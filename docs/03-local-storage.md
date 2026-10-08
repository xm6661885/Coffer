# 03 · 本机空间、Files App、分享导入、本地文件操作

## 1. 沙盒布局
| 路径 | 用途 | Files App 可见 |
|---|---|---|
| `Documents/` | “My iPhone” 根目录，用户文件全部在这里 | 是（On My iPhone › Coffer） |
| `Documents/Inbox/` | 系统“打开方式”投递的临时目录（系统创建） | 是，但 UI 中隐藏，见 §3 |
| `Library/Application Support/Coffer/` | JSON 存储 | 否 |
| `Library/Caches/Coffer/Thumbnails/` | 缩略图缓存 | 否 |
| `Library/Caches/Coffer/Remote/<locationKey>/...` | WebDAV 文件预览缓存 | 否 |
| `Library/Caches/Coffer/Partial/<taskID>/` | 下载中的分段文件 | 否 |
| `tmp/` | 压缩/上传临时文件 | 否 |

`LocalFileProvider.rootURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]`。
`url(for path: String) -> URL`：`path == "/"` 返回 rootURL，否则 `rootURL.appending(path: String(path.dropFirst()), directoryHint: ...)`。所有路径都必须用此函数转换，禁止字符串拼接 URL。

## 2. Files App 集成
Info.plist 已设置（不要删除）：
- `UIFileSharingEnabled = YES`
- `LSSupportsOpeningDocumentsInPlace = YES`
这两项让 `Documents/` 出现在 Files App 的 “On My iPhone › Coffer”，用户可在 Files App 中直接浏览、打开、拖入、拷出文件。不需要写 File Provider 扩展。

首次启动时不要在 `Documents/` 里创建任何占位文件或示例文件。

外部（Files App、电脑 Finder 的文件共享）修改了文件后，App 内必须自动刷新：
- `DirectoryWatcher`：用 `DispatchSource.makeFileSystemObjectSource(fileDescriptor: open(path, O_EVTONLY), eventMask: [.write, .rename, .delete, .extend], queue: .main)` 监听当前浏览的本地目录；事件回调去抖 0.3s 后调用 `BrowserModel.reload()`。`BrowserView` 出现时开始监听，消失时 `cancel()` 并 `close(fd)`。
- 另外在 `scenePhase` 变为 `.active` 时刷新当前可见目录。

## 3. 从外部导入（分享菜单 / 打开方式）
Info.plist 已声明 `CFBundleDocumentTypes`（`public.item`，Role Viewer，Rank Alternate）。效果：任意 App 的分享面板里选择 “Coffer”（或 “Open in Coffer”），系统会把文件复制到 `Documents/Inbox/` 或以 security-scoped URL 交给 App，并调用 `onOpenURL`。

### ImportService
```swift
@MainActor @Observable final class ImportService {
    struct PendingImport: Identifiable { let id = UUID(); var urls: [URL] }
    var pending: PendingImport?          // 非 nil 时 RootView 弹出导入面板
    func handleOpenURL(_ url: URL)        // 由 CofferApp.onOpenURL 调用；把 url 追加到 pending（0.5s 内连续到达的合并为一次）
    func importFiles(_ urls: [URL], to dirPath: String, move: Bool) async -> [FileItem]
}
```
`importFiles` 规则：
1. 对每个 url：`let scoped = url.startAccessingSecurityScopedResource()`，完成后 `if scoped { url.stopAccessingSecurityScopedResource() }`。
2. 目标名冲突时用 `PathUtil.uniqueName` 自动改名（导入不弹冲突框）。
3. 来源在 `Documents/Inbox/` 内时使用 `moveItem`；否则用 `NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { readURL in try? FileManager.default.copyItem(at: readURL, to: dst) }` 复制。
4. 完成后删除 `Documents/Inbox/` 中已经处理的文件；若 Inbox 为空则删除 Inbox 目录。
5. 结束后 `toast.show("Imported \(n) item(s)", symbol: "tray.and.arrow.down")`，并在 Toast 上提供 `Show` 动作：切到 Files Tab 并导航到目标文件夹。

### 导入面板（RootView 上 `.sheet(item: $importer.pending)`）
- `.presentationDetents([.medium])`，`NavigationStack` 内：
  - 标题 `Save to Coffer`（inline）。
  - 列表第一段：每个待导入文件一行（FileIconView + 名称 + 大小），最多显示 5 行，多于 5 行显示 `and N more`。
  - 第二段：`Destination` 行，显示当前目标（默认 `My iPhone`，即 `/`，记住上次选择存在 `AppSettings.lastImportDestination`），点击进入 `DestinationPicker`（仅本地位置）。
  - 工具栏左 `Cancel`（取消时：删除 Inbox 中对应文件），右 `Save`（`.buttonStyle(.glassProminent)`，tint pink）。
- 冷启动时 onOpenURL 也会触发，确保 `ImportService` 在 `CofferApp` 中已创建。

### Files Tab 内的导入入口（BrowserView 的 + 菜单）
- `Import from Files`：`.fileImporter(isPresented:, allowedContentTypes: [.item], allowsMultipleSelection: true)` → `importFiles(to: 当前目录, move: false)`。
- `Import from Photos`：`PhotosPicker(selection:, maxSelectionCount: nil, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current)`。对每个 `PhotosPickerItem` 使用 `loadTransferable(type: FileTransferable.self)`，其中
  ```swift
  struct FileTransferable: Transferable {
      let url: URL
      static var transferRepresentation: some TransferRepresentation {
          FileRepresentation(importedContentType: .item) { received in
              let dst = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: received.file.lastPathComponent)
              try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
              try FileManager.default.copyItem(at: received.file, to: dst)
              return FileTransferable(url: dst)
          }
      }
  }
  ```
  然后 `importFiles([url], to:, move: true)`。保留原始文件名（HEIC 就是 HEIC）。

## 4. 导出到外部
- `Share`（长按菜单与选择模式）：统一用 `ActivityView`（`UIActivityViewController` 的 `UIViewControllerRepresentable`），放在 `.sheet` 中并设 `.presentationDetents([.medium, .large])`。本地文件直接传文件 URL；远程文件先用 `RemoteCache.fetch` 下载到缓存，下载期间显示 toast `Preparing…`（带进度百分比），完成后再弹出。不要用 `ShareLink`（它无法延迟准备远程内容）。
- `Export to Files…`：`UIDocumentPickerViewController(forExporting: urls, asCopy: true)` 的 `UIViewControllerRepresentable`，放在 `.sheet` 中。远程文件同样先下载到缓存。

## 5. LocalFileProvider 实现细节
全部在后台执行：每个方法内部 `try await Task.detached(priority: .userInitiated) { ... }.value`。

- `list`：`contentsOfDirectory(at:includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .isSymbolicLinkKey], options: [])`。不要用 `.skipsHiddenFiles`。根目录列表中排除 `Inbox`（当 `path == "/"` 且名字 == "Inbox" 且为目录时跳过）。符号链接解析其目标类型。
- `createFolder`：先 `PathUtil.isValidName`，存在则 throw `.alreadyExists`，`createDirectory(withIntermediateDirectories: false)`。
- `createFile`：`data.write(to:, options: .withoutOverwriting)`。
- `rename`：同目录 `moveItem`。若新名字与旧名字只有大小写不同（APFS 大小写不敏感），先移动到临时名 `.<uuid>` 再移动到新名。目标存在 → `.alreadyExists`。
- `delete`：`removeItem`。不做回收站（简单起见），但 UI 一定要确认。
- `copy`/`move`：目标存在且 `overwrite` → 先 `removeItem` 目标再操作；`move` 用 `moveItem`；`copy` 用 `copyItem`（APFS 自动克隆，秒级）。
- 防呆：不允许把文件夹复制/移动到它自己或其子目录（`PathUtil.isAncestor(item.path, of: destPath)`），throw `.other("You can't move a folder into itself.")`。
- 磁盘空间：`URLResourceValues.volumeAvailableCapacityForImportantUsage`，在 HomeView 显示（见 04）。

## 6. FileOperations（统一的增删改入口，UI 只调用它）
```swift
@MainActor @Observable final class FileOperations {
    enum ConflictChoice { case replace, keepBoth, skip }
    struct ConflictPrompt: Identifiable { let id = UUID(); let name: String; let remaining: Int; let resume: (ConflictChoice, _ applyToAll: Bool) -> Void }
    var conflict: ConflictPrompt?      // RootView 弹 confirmationDialog

    func createFolder(named: String, location: LocationID, in dir: String) async -> FileItem?
    func createTextFile(named: String, location: LocationID, in dir: String) async -> FileItem?
    func rename(_ item: FileItem, to newName: String) async -> FileItem?
    func delete(_ items: [FileItem]) async
    /// 剪贴板粘贴 / Move… / Copy to… 都走这里
    func transfer(_ items: [FileItem], to destLocation: LocationID, destDir: String, move: Bool) async
}
```
`transfer` 逻辑：
1. 获取目标目录现有名字集合（一次 list）。
2. 逐项处理。若同名存在：如果之前选择过 “Apply to all” 则沿用，否则设置 `conflict` 并 `await withCheckedContinuation` 等待用户选择。
   - 对话框（`.confirmationDialog`）：标题 `"\(name)" already exists`，按钮依次为 `Replace`（role destructive）、`Keep Both`、`Skip`；当 remaining > 0 时再加 `Replace All`（destructive）、`Keep Both for All`；最后 `Cancel`（role cancel，取消整个批次剩余项）。
   - 所有方法内部 catch 错误并调用 `toast.show(error:)`，失败返回 nil。
   - Keep Both → `PathUtil.uniqueName`。
3. 同一位置：调用 provider.copy/move（WebDAV 走服务端 COPY/MOVE，见 05）。
4. 跨位置（本地↔WebDAV、WebDAV A↔WebDAV B）：交给 `TransferManager` 创建任务（下载/上传，WebDAV→WebDAV 是“下载到 tmp 再上传”的组合任务），move 时在任务成功后删除源。立刻 toast `Added \(n) transfer(s)`，提供 `View` 动作打开传输面板。
5. 本地同位置的操作完成后 toast：`Copied 3 items` / `Moved 3 items`。
6. 发出 `NotificationCenter` 通知 `.cofferDirectoryChanged`，userInfo `["location": LocationID, "path": String]`，对源目录和目标目录各发一次；所有 BrowserModel 监听并在路径匹配时 reload。
