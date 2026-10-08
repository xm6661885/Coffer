# 09 · 分阶段实施清单

规则：**一次只做一个阶段**。每个阶段结束时运行 `./scripts/build.sh`，直到输出 `BUILD OK` 才进入下一阶段。任何阶段都不要留下 `// TODO`、空实现、`fatalError()`（`init` 除外）、被注释掉的代码。不要删改前面阶段已经完成的功能。

每阶段完成后，在 `docs/PROGRESS.md` 里追加一行：`- [x] P3 · 本地浏览与文件操作 · BUILD OK`。

---

## P0 · 工程骨架与编译通过
- 运行 `./scripts/fetch-vlckit.sh`（若 `Vendor/MobileVLCKit.xcframework` 不存在）。它下载约 250 MB，可中断后重跑续传。完成后 `ls Vendor/MobileVLCKit.xcframework` 应看到 `ios-arm64_armv7_armv7s`（或类似）与 `ios-arm64_x86_64-simulator` 两个目录。
- 运行 `./scripts/build.sh`，确认现有占位 App 编译通过（此时还链接了 VLCKit；若有链接错误，报错后再处理，不要擅自移除依赖）。
- 建立 `Sources/` 下的目录结构（可先建空目录 + 每个文件的最小可编译内容）。
- 删除 `Sources/CofferApp.swift` 中的占位视图，替换为正式 `App/` 目录下的文件，实现：TabView 双 Tab（内容分别为 `Text("Files")`、`Text("Tools")`）、主题 token（`Design/Theme.swift` 全部颜色与字体）、`.tint(.pinkInk)`、`UINavigationBar.appearance()` 衬线标题。
- 验收：运行后看到米黄色背景 + 底部玻璃 Tab 栏（两个 Tab）+ 衬线大标题；深色模式下颜色正确。

## P1 · 数据层与本地文件系统
- `LocationID`、`FileItem`、`FileKind`、`PathUtil`、`Formatters`、`JSONStore`、`Keychain`、`AppSettings`。
- `FileProvider` 协议 + `LocalFileProvider` 全实现。
- `FileProviderRegistry`（只含 local）、`Clipboard`、`ToastCenter`（含 Toast UI）、`FileOperations`（含冲突对话框）。
- 验收：代码可编译；临时用一个测试按钮验证 `list("/")` 返回 Documents 内容、能创建/重命名/删除文件夹且 toast 正常。测试代码在进入 P2 前删除。

## P2 · 首页与文件浏览
- `RootView`、`Navigator`、`HomeView`（My iPhone 行 + Recents + 空 WebDAV 段 + 设置入口按钮先禁用/隐藏）。
- `BrowserView` + `BrowserModel` + `FileRow` + 网格单元 + 排序 + 搜索 + 下拉刷新 + 空状态。
- 导航：点击目录 push、标题菜单面包屑、返回手势。
- DirectoryWatcher + `.cofferDirectoryChanged` 通知刷新。
- 验收：能浏览 Documents，进入多级目录，排序/搜索/列表网格切换正常，外部改动能在回到前台后刷新。

## P3 · 文件操作交互
- 选择模式（导航栏变化、底部工具栏、全选、Done）。
- 长按菜单（全部条目）、左滑/右滑、重命名 sheet（含扩展名保护与校验）、新建文件夹/新建文本文件、删除确认。
- 复制/剪切/粘贴 + PasteBar + 冲突处理 + Move…/Copy to…（DestinationPicker）。
- InfoSheet、Share/Export、压缩与解压（zip）、拖放（可放到最后）。
- 验收：完成一遍真实操作流程：新建文件夹 → 复制文件进去 → 粘贴两次（自动改名）→ 剪切到别处 → 重命名（只选中主名）→ 删除；每一步的 toast、动画、冲突对话框都与文档一致。

## P4 · 预览
- `PreviewRouter` + TextPreview（Rendered/Source、高亮、编码、查找、行号）+ WebRenderView + TextDecoding。
- ImagePreview（缩放、翻页、GIF…）、PDFPreview、QuickLookPreview、FontPreview、UnsupportedPreview、ArchivePreview。
- ThumbnailService + FileIconView 接入列表与网格。
- 验收：md/html/json/csv/代码/txt 都能正常渲染与切换源码；图片可缩放翻页；pdf/office 可看；zip 可列出与解压。

## P5 · WebDAV
- `WebDAVServer` + `AddServerView`（含 Test Connection）+ Keychain + registry 持久化 + HomeView 服务器段（含编辑/删除/排序）。
- `WebDAVClient` + `PropfindParser` + `DirectoryCache` + `WebDAVFileProvider`。
- 远程目录浏览（缓存优先 + 后台刷新 + Offline 提示）、远程新建/重命名/删除/COPY/MOVE。
- `RemoteCache` + 预览时自动下载（DownloadingView）+ Make Available Offline。
- 验收：对一个真实 WebDAV（例如本机自建或 Nextcloud）完成浏览、上传（新建文本文件）、重命名、删除、COPY/MOVE、预览图片与文本、离线重进目录仍显示上次列表。

## P6 · 传输引擎
- `TransferTask` + `TransferManager`（队列、并发、NWPathMonitor、后台任务、持久化恢复）。
- `SegmentedDownloader`（多连接、Range、断点续传、退避重试）+ `Uploader`（临时名 + MOVE + 校验）。
- 跨位置复制/移动接入 `FileOperations`；`TransfersView` + 首页圆环进度 + 文件行内进度。
- 验收：下载一个 > 200 MB 的远程文件，中途关掉网络（应显示 Waiting for network，恢复后续传）、中途杀掉 App（重进后自动续传）、下载完成后大小一致；上传一个 50 MB 文件到 WebDAV 且远端大小一致；跨位置 move 完成后源文件删除。

## P7 · 音频与音乐
- `PlayerBackend` + `AVPlayerBackend` + `VLCBackend` + `MediaSourceResolver` + `MetadataLoader`。
- `AudioPlayer`（队列/随机/循环/倍速/睡眠定时/续播/会话与中断）+ `NowPlayingCenter`。
- `MiniPlayerView`（accessory，expanded/inline）+ `MusicPlayerView`（全屏）+ `QueueView` + `Scrubber`。
- 文件浏览器点击音频即播；长按菜单的 Play Next / Add to Queue / Add to Playlist 接入。
- 验收：浏览文件夹点击一首歌开始播放，迷你播放器出现；全屏播放器可拖动进度、切歌、倍速、循环、随机、睡眠定时；锁屏与控制中心可控制并显示封面；App 退到后台继续播放；点其他音频文件替换队列。

## P8 · 视频
- `VideoPlayerModel` + `VideoPlayerView` + `VideoSurface` + 手势层 + `SystemVolume` + `OrientationController`。
- `PiPController`（AV 后端）+ 后台继续音频 + 外挂字幕（SubtitleParser）+ 内置轨道选择。
- 浏览器点击视频即打开；续播提示 `Resumed from 12:34`；连播与 Up Next 卡片。
- 验收：mp4 与 mkv 各测一个；双击快进快退、长按倍速、横拖定位、竖拖亮度/音量、捏合 fill/fit、旋转按钮、锁定、画中画、后台声音、字幕加载均正常。

## P9 · 工具 Tab
- `ToolsView` 卡片布局、Continue Watching、Playlists（`PlaylistStore` + `AddToPlaylistSheet` + `PlaylistDetailView` + `MediaPicker`）。
- `MusicLibrary` + `MusicLibraryView`、`VideoLibrary` + `VideoLibraryView`。
- `TextEditorHome` + `TextEditorView` + `CodeTextView`（含行号、键盘辅助栏、自动保存、编码、远程保存冲突）。
- `SettingsView` + `LicensesView` 全部项接线。
- 验收：从 Tools 进入三个工具都能用；播放列表可创建、加歌、排序、删除；编辑器能新建/编辑/保存本地与远程文本并保持编码；设置项全部生效（改主题立刻变色、改并行连接数影响下次下载）。

## P10 · 打磨与验收
- 全部动画与触感按 01/04/07 文档检查一遍；深色模式逐屏检查；横屏检查（文件浏览 + 播放器）。
- 空状态、错误状态、离线状态逐项检查（把网络断掉、把服务器 URL 改错、删除一个正在播放的文件）。
- 无障碍：所有图标按钮补 `.accessibilityLabel`；Dynamic Type 到大号不截断（文件名可截断）。
- 性能：1000 个文件的目录滚动不掉帧（用 `List` 默认懒加载，不要用 `VStack` 铺行）；缩略图异步不阻塞。
- 移除所有测试代码、`print`、调试按钮。
- 最终 `./scripts/build.sh` → `BUILD OK`。
- 在 `docs/PROGRESS.md` 末尾写一段 `## Final notes`：说明哪些地方与文档有偏差、哪些功能没做、已知问题。

---

## 全局注意事项（易错点）
1. `List` 里放自定义行时不要设置固定高度，用 `.listRowInsets` 调整内边距。
2. `@Observable` 类的属性在视图里直接读写即可（不需要 `@Bindable`，除非需要绑定；需要绑定时用 `@Bindable var model = model`）。
3. SwiftUI 的 `.sheet` 里需要独立的 `NavigationStack`，否则没有标题栏。
4. `VLCMediaPlayer` 的回调线程不是主线程，必须回到主线程更新状态。
5. VLC 必须在**播放前**设置好 `drawable`，并且 drawable 视图必须已经在窗口层级中且尺寸非零；切换视频时先 `player.stop()` 再换 drawable。
6. `AVAudioSession` 切换 mode 时若正在播放会中断，只在开始播放前设置。
7. 所有 `URLSession` 请求都要带 `Authorization`（除非服务器不支持 Basic）。
8. 大文件处理：读取文本用 `FileHandle` 分段或 `Data(contentsOf:options:.mappedIfSafe)`，不要一次性把 2 GB 读进内存。
9. iPhone 横屏时 `safeAreaInsets` 变化，播放器控件必须基于安全区布局。
10. 每次 `.sheet` / `.fullScreenCover` 里若需要主题色，确保背景设为 canvas（系统默认在深色模式下是黑色，会与设计冲突）。
