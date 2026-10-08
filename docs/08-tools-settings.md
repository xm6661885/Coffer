# 08 · 工具 Tab 与设置

## 1. ToolsView（Tools Tab 根）
`NavigationStack`，大标题 `Tools`。`ScrollView` + `VStack(spacing: 24)`，左右边距 20，背景 canvas。

### 1.1 顶部：三张工具卡片（`VStack(spacing: 12)`：第一行 `HStack(spacing: 12)` 两张等宽卡片 Music / Videos，第二行一张全宽卡片 Text Editor）
```
┌──────────────┐ ┌──────────────┐
│ music.note   │ │ film         │
│              │ │              │
│ Music        │ │ Videos       │
│ 248 songs    │ │ 31 videos    │
└──────────────┘ └──────────────┘
┌───────────────────────────────┐
│ square.and.pencil  Text Editor  3 recent >│
└───────────────────────────────┘
```
- 卡片：背景 surface，圆角 22，内边距 18，0.5pt hairline 描边，高 132（全宽卡片高 72，横向布局）。
- 图标：28pt，pinkInk，`.symbolRenderingMode(.hierarchical)`，左上。
- 标题 `.cofferHeadline`，副标题 caption inkSecondary（来自 MusicLibrary/VideoLibrary 的计数；扫描中显示 `Scanning…`）。
- 点击：`NavigationLink(value: ToolRoute.music / .videos / .textEditor)`，卡片使用 `.matchedTransitionSource` + 目标 `.navigationTransition(.zoom)`。
- 按压反馈：`.buttonStyle(.plain)` 并自定义 `PressableCardStyle`（按下 `scaleEffect(0.97)`，`.snappy`）。

### 1.2 Continue Watching / Continue Listening（无内容则隐藏）
- 段标题 `Continue Watching`（`.cofferHeadline`，左对齐），下面水平 `ScrollView(.horizontal)`：每项 160×90 视频缩略图卡片（圆角 14），底部叠一条 3pt 进度条（pink），下方文件名（caption，2 行）。点击直接打开视频播放器并续播。长按菜单：`Remove from Continue Watching`、`Show in Files`。
- 数据源：PlaybackPositionStore 中有进度的视频，按最近更新时间排序，最多 10 个。
- `Continue Listening`：长音频（>20 分钟）同样规则，卡片为正方形 120×120 封面。

### 1.3 Playlists
- 段标题行：`Playlists` + 右侧 `+` 按钮（`plus`，`.buttonStyle(.glass)` `.buttonBorderShape(.circle)` `.controlSize(.small)`）→ 新建播放列表 sheet（与 RenameSheet 同外观，标题 `New Playlist`，默认名 `Playlist 1`…，再加一个分段 Picker `Music` / `Video` 选择类型）。
- 列表：`VStack` 中每个播放列表一行（不使用 List，因为在 ScrollView 里）：48×48 封面拼贴（取前 4 项的封面 2×2；不足时显示 `music.note.list` / `play.rectangle.on.rectangle` 图标于 surfaceSunken）+ 名称 + `24 songs · 1 hr 32 min` + chevron。行背景 surface 圆角 14。
- 点击 → `PlaylistDetailView`。长按菜单：`Play`、`Shuffle`、`Rename`、`Delete`（确认）。
- 空：一张 surface 背景圆角 14 的卡片，内含文字 `Create a playlist to group songs or videos from anywhere, including WebDAV.`（inkSecondary）+ 按钮 `New Playlist`（`.buttonStyle(.glass)`）。

### 1.4 Settings 入口
导航栏右上 `gear` 按钮 → push `SettingsView`（与首页菜单里的 Settings 是同一个页面）。

## 2. Playlist 模型
```swift
struct Playlist: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case music, video }
    var id = UUID(); var name: String; var kind: Kind
    var items: [MediaRef]; var created = Date(); var modified = Date()
}
@MainActor @Observable final class PlaylistStore {
    private(set) var playlists: [Playlist]           // playlists.json
    func create(name: String, kind: Playlist.Kind) -> Playlist
    func rename(_ id: UUID, to: String); func delete(_ id: UUID)
    func add(_ refs: [MediaRef], to id: UUID)          // 去重（同 id 不重复添加），toast "Added 3 items to \"Road Trip\""
    func remove(at: IndexSet, from id: UUID); func move(from: IndexSet, to: Int, in id: UUID)
}
```
MediaRef 可以指向本地或 WebDAV 文件，混合在同一列表。若文件不存在（播放时 notFound），行显示为 50% 不透明度，副标题 `Unavailable`，播放时跳过。

### AddToPlaylistSheet
`.sheet` `.presentationDetents([.medium, .large])`，标题 `Add to Playlist`。第一行 `New Playlist…`（plus），下面是与当前选择类型匹配的播放列表（音频 → music 列表；视频 → video 列表；混合选择 → 只显示 music 列表并忽略视频）。点击即添加并关闭。

### PlaylistDetailView
- 顶部 Header（不在导航栏里，在 List 的第一个 Section，无背景）：封面拼贴 160×160 圆角 22，名称（cofferTitle，可点击重命名），`24 songs · 1 hr 32 min`，两个按钮并排：`Play`（play.fill，`.glassProminent` pink，onPink 文字）与 `Shuffle`（shuffle，`.glass`），等宽，高 48。
- 下面 List 显示条目（音乐：封面 40 + 标题 + 艺术家 + 时长；视频：缩略图 64×36 + 名称 + 时长 + 进度条（如有续播进度））。
- 点击条目：音乐 → 以整个播放列表为队列从该项播放（sourceTitle = 播放列表名）；视频 → 打开视频播放器，playlist = 该播放列表全部视频。
- 右上 `Edit` 按钮（系统 `EditButton()`）：编辑模式可拖动排序与删除。右上另有 `+` → 打开 `MediaPicker`：一个复用 BrowserView 选择模式的文件选择器（sheet，标题 `Add Songs` / `Add Videos`，从位置根开始浏览，只允许选择对应类型的文件，底部按钮 `Add (N)`）。

## 3. 音乐库 MusicLibrary / MusicLibraryView
### 索引
- 扫描范围：本机 `Documents/` 全部（递归）中的音频文件；另外用户可以在设置中添加 WebDAV 文件夹为“音乐来源”（`settings.musicSources: [BrowserRoute]`），对这些文件夹做递归 PROPFIND（Depth 1 逐层，最多 5000 个文件）。
- 索引结果 `music-index.json`：`[MediaRef: TrackMetadata + addedAt]`。启动后 3 秒在后台增量扫描（比较 modified），下拉刷新强制重新扫描。
- 元数据读取并发 4，逐个更新（UI 实时出现）。WebDAV 文件只读文件名，不下载：标题 = 文件名去扩展名，艺术家/专辑为空（UI 显示 `Unknown Artist` / `Unknown Album`）；播放过一次后用播放器读到的元数据回填索引。

### 界面
- 大标题 `Music`，`.searchable(prompt: "Search songs, artists, albums")`。
- 顶部分段 Picker（放在 List 的第一个 Section 里，不放在导航栏）：`Songs` / `Albums` / `Artists` / `Folders`。
- Songs：按标题 `localizedStandardCompare` 排序（不做右侧字母索引）；List 行：封面 44（圆角 6）+ 标题 + `艺术家 · 专辑` + 时长（右侧，timecode）。顶部两按钮行 `Play` / `Shuffle`（同 PlaylistDetailView）。点击 → 以当前（已过滤、已排序）列表为队列播放。
- Albums：2 列网格，封面方块（圆角 14）+ 专辑名 + 艺术家；点击 → 专辑详情（Header + 曲目按 track number / 文件名排序）。
- Artists：List，点击 → 该艺术家全部歌曲。
- Folders：按所在文件夹分组列出（文件夹名 + 歌曲数），点击 → 该文件夹歌曲列表。
- 每首歌长按菜单：`Play Next`、`Add to Queue`、`Add to Playlist…`、`Show in Files`、`Get Info`。
- 正在播放的歌曲行：标题 pinkInk，左侧封面上叠加 `waveform` 符号动画。
- 空：`ContentUnavailableView("No music yet", systemImage: "music.note", description: Text("Add audio files to My iPhone or choose a WebDAV music folder in Settings."))` + 按钮 `Open Files`（切到 Files Tab）。

## 4. 视频库 VideoLibrary / VideoLibraryView
- 扫描范围同音乐（`settings.videoSources`）。索引含时长、分辨率（本地读取 `AVURLAsset` tracks naturalSize；VLC 格式用 `VLCMedia.parse`）与缩略图（ThumbnailService；VLC 格式用 `VLCMediaThumbnailer` 生成，失败则图标）。
- 界面：大标题 `Videos`，searchable。Picker：`All` / `Folders`。
- All：2 列网格（iPad 自适应 `GridItem(.adaptive(minimum: 170))`），每项 16:9 缩略图（圆角 14）+ 右下角时长胶囊（`.glassEffect(.regular, in: .capsule)`，caption timecode）+ 有续播进度时底部 3pt pink 进度条；下方 2 行文件名。排序 Menu（右上）：`Recently Added`、`Name`、`Duration`、`Size`。
- 点击 → 视频播放器，playlist = 当前显示顺序的全部视频。
- 长按菜单：`Play`、`Play from Beginning`、`Add to Playlist…`、`Mark as Watched`（清除进度）、`Show in Files`、`Get Info`。

## 5. 文本编辑器
### 5.1 TextEditorHome（Tools › Text Editor）
- 大标题 `Text Editor`。
- 第一段：两个按钮行：`New Document`（square.and.pencil）→ 在 `My iPhone` 根目录（`/`）创建 `Untitled.txt`（重名加数字）并打开编辑器；`Open…`（folder）→ 打开 DestinationPicker 风格的文件选择器（可选择文本类文件，任意位置）。
- 第二段 `Recent`：最近编辑过的文本文件（RecentsStore 中 kind.isTextual 的项，最多 20），行：图标 + 名称 + 位置 · 修改时间。左滑 `Remove`。

### 5.2 TextEditorView
以 `.fullScreenCover` 打开（从文件浏览器 `Edit` / 新建文本文件 / Tools 打开都一样），内部 `NavigationStack`。
- 导航栏：左上 `Done`（若有未保存修改：先自动保存，再关闭；保存失败时弹 confirmationDialog `Couldn't save changes` → `Try Again` / `Discard Changes`（destructive） / `Cancel`）。标题 = 文件名（点按 → `.toolbarTitleMenu`：`Rename`、`Show in Files`、`Get Info`）。`navigationSubtitle`：`Edited` / `Saved` / `Saving…` / `Not saved`。
- 右上：`undo`（arrow.uturn.backward）、`redo`（arrow.uturn.forward）（`UndoManager`，不可用时禁用）、`magnifyingglass`（系统查找替换：`textView.findInteraction?.presentFindNavigator(showingReplace: true)`）、`ellipsis.circle` Menu：
  - `Preview`（markdown / html 时出现）→ 推入 TextPreview(Rendered)，内容为当前未保存文本
  - `Wrap Lines` Toggle、`Line Numbers` Toggle（默认开）、`Text Size` 子菜单
  - `Encoding` 子菜单（显示当前，切换后按新编码重新解码原始数据；保存时用当前编码）
  - `Line Endings` 子菜单（LF / CRLF，显示检测结果）
  - `Share`
- 编辑区 `CodeTextView`（UIViewRepresentable 包 `UITextView`）：
  - 字体：等宽 `UIFont.monospacedSystemFont(ofSize: 15)`（Text Size 档 13/15/18），文字色 Ink，背景 Canvas，`textContainerInset = (12, 16, 40, 16)`。
  - `autocorrectionType = .no`、`autocapitalizationType = .none`、`smartQuotesType = .no`、`smartDashesType = .no`、`spellCheckingType = .no`（代码与配置文件不要被修改引号）；`.txt` 与 `.md` 文件时开启 spellChecking 与 autocorrection。
  - `isFindInteractionEnabled = true`。
  - 软换行关闭时：`textContainer.widthTracksTextView = false`、`textContainer.size = CGSize(width: 100_000, height: .greatestFiniteMagnitude)`，允许水平滚动。
  - 行号：左侧 gutter（UITextView 子类，`draw(_:)` 中在可见区域按行绘制行号，或用一个同步滚动的旁置 UIView）。宽度按位数自适应（最小 3 位），行号颜色 InkTertiary，与正文同字体 0.85 倍大小，gutter 背景 Canvas，右侧 0.5pt Hairline。软换行开启时行号只标记逻辑行的第一行。
  - 语法高亮：不做（编辑器保持纯文本，追求稳定；高亮只在预览中做）。
  - 键盘辅助栏 `inputAccessoryView`：`UIInputView(frame: CGRect(x: 0, y: 0, width: 0, height: 44), inputViewStyle: .keyboard)`（与系统键盘外观融合），内含一个水平滚动的 UIStackView 按键条，按键：`Tab`（插入 4 空格或 `\t`，取决于文件现有缩进检测）、`←` `→`（移动光标）、`{` `}` `(` `)` `[` `]` `"` `'` `<` `>` `/` `\` `#` `*` `-` `=` `:` `;` `|`、最右 `keyboard.chevron.compact.down`（收起键盘）。按键为圆角 8 的小方块，`UIButton.Configuration.gray()`。
- 保存：
  - 自动保存：停止输入 2 秒后保存；切到后台时保存；关闭时保存。
  - `Cmd+S`（外接键盘）：`.keyboardShortcut("s", modifiers: .command)` 隐藏按钮触发保存。
  - 本地：写入临时文件后 `replaceItemAt`（原子替换），保持原编码与换行符。
  - 远程：先保存到 RemoteCache 中的本地副本，再 PUT 上传（直接 `client.put`，小文件；> 5 MB 时走 Uploader）。上传前比较远端 etag（PROPFIND depth 0），若与打开时不同 → 弹 confirmationDialog `This file changed on the server` → `Overwrite`（destructive）/ `Save as Copy`（保存为 `name (Conflict).ext`）/ `Cancel`。
  - 大文件：> 10 MB 的文本以只读打开，顶部提示条 `This file is too large to edit. Opened as read-only.`。
- 外部变化：编辑本地文件期间，若 DirectoryWatcher 检测到文件被外部修改且编辑器内无未保存修改 → 自动重新加载；有未保存修改 → 提示条 `Changed outside Coffer · Reload`。

## 6. 设置 SettingsView
`Form`，背景 canvas，行背景 surface。标题 `Settings`。顶部 Header：CofferGlyph 48pt pinkInk + `Coffer` (cofferTitle) + `Version 1.0 (1)` caption，居中。

| Section | 项 | 类型 | 默认 |
|---|---|---|---|
| Appearance | `Theme` | Picker（menu）：System / Light / Dark | System |
| Files | `Show Hidden Files` | Toggle | Off |
| | `Show File Extensions` | Toggle | On |
| | `Folders on Top` | Toggle | On |
| | `Default View` | Picker：List / Icons | List |
| Playback | `Tap Audio Opens Player` | Toggle | Off |
| | `Skip Interval` | Picker：5 / 10 / 15 / 30 seconds | 10 |
| | `Long-Press Speed` | Picker：1.5x / 2x / 3x | 2x |
| | `Auto-Rotate Videos` | Toggle | On |
| | `Auto Picture in Picture` | Toggle | On |
| | `Play Video Audio in Background` | Toggle | On |
| | `Resume Playback` | Toggle（记住进度） | On |
| Remote | `Stream Remote Media` | Toggle | On |
| | `Load Thumbnails for Remote Images` | Toggle | On |
| | `Music Sources`（NavigationLink → 列表，可添加/删除 WebDAV 文件夹，添加用 DestinationPicker） | | 空 |
| | `Video Sources`（同上） | | 空 |
| Transfers | `Simultaneous Transfers` | Stepper 1…6 | 3 |
| | `Only on Wi-Fi` | Toggle | Off |
| Storage | `Remote Cache` | 显示大小（`1.2 GB`）；Picker `Cache Limit` | 2 GB |
| | `Clear Cache`（danger 文字按钮，确认对话框 `Clear 1.2 GB of cached files?`，`Keep offline files` 不受影响） | | |
| | `Clear Thumbnails` | | |
| About | `Licenses`（→ LicensesView：VLCKit LGPL-2.1、ZIPFoundation MIT、marked MIT、DOMPurify Apache-2.0/MPL-2.0、highlight.js BSD-3-Clause 的名称与一句说明） | | |

`AppSettings`：`@Observable`，每个属性 `didSet { UserDefaults.standard.set(...) }`，init 时读取。主题通过 RootView `.preferredColorScheme(settings.theme.colorScheme)`（System → nil）。
