# 07 · 音频与视频播放

两套播放体系：
- **AudioPlayer**（全局单例）：音乐。后台播放、锁屏控制、队列、迷你播放器。
- **VideoPlayerModel**（每次打开视频创建）：全屏视频，手势、画中画、旋转。
两者共享 `PlayerBackend` 抽象。打开视频时暂停音乐；视频关闭后**不**自动恢复音乐。

## 1. 音频会话
`AppDelegate.didFinishLaunching`：
`try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)`。
之后每次开始播放前由各自的播放器重新设置并激活：音乐 `setCategory(.playback, mode: .default)`，视频 `setCategory(.playback, mode: .moviePlayback)`，然后 `setActive(true)`。不要使用 `policy: .longFormAudio`。
- 处理中断：监听 `AVAudioSession.interruptionNotification`：began → 暂停（记录 wasPlaying）；ended 且 options 含 `.shouldResume` 且 wasPlaying → 继续。
- 处理耳机拔出：`routeChangeNotification` 且 reason == `.oldDeviceUnavailable` → 暂停。
- Info.plist 已含 `UIBackgroundModes = audio`。

## 2. PlayerBackend 协议
```swift
@MainActor protocol PlayerBackend: AnyObject {
    var onStateChange: ((PlaybackState) -> Void)? { get set }   // 播放/暂停/缓冲/结束/失败
    var onTime: ((_ current: Double, _ duration: Double) -> Void)? { get set }   // 每 0.25s
    func load(_ source: MediaSource) async throws
    func play(); func pause()
    func seek(to seconds: Double) async
    var rate: Float { get set }                    // 0.5 … 3.0
    var volume: Float { get set }                  // 软件音量（0…1），一般保持 1
    var currentTime: Double { get }; var duration: Double { get }
    // 轨道
    var audioTracks: [MediaTrack] { get }; var subtitleTracks: [MediaTrack] { get }
    func selectAudioTrack(_ id: Int?); func selectSubtitleTrack(_ id: Int?)
    func addExternalSubtitle(_ url: URL)
    var subtitleDelay: Double { get set }          // 秒，VLC 原生支持；AV 后端在自己的字幕渲染中偏移
    func stop()
}
enum PlaybackState { case idle, loading, playing, paused, buffering, ended, failed(String) }
struct MediaTrack: Identifiable, Hashable { let id: Int; let name: String }
struct MediaSource { let url: URL; let headers: [String: String]; let isLocal: Bool; let title: String }
```

### AVPlayerBackend
- `AVPlayer`，`automaticallyWaitsToMinimizeStalling = true`。
- 时间观察 `addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4))`。
- 倍速：设置 `player.defaultRate = rate`，播放中 `player.rate = rate`；`currentItem.audioTimePitchAlgorithm = .timeDomain`（变速不变调）。
- 结束：`AVPlayerItem.didPlayToEndTimeNotification`。
- 失败：观察 `item.status == .failed` → `onStateChange(.failed)`，上层自动切换 VLC 后端重试。
- 音轨/字幕：`AVMediaSelectionGroup`（`asset.loadMediaSelectionGroup(for: .audible / .legible)`）。外挂字幕：用 SubtitleParser 解析 SRT/VTT 为 `[Cue(start,end,text)]`，由 VideoPlayerView 自己在画面底部渲染（白字黑描边，`.shadow(color: .black, radius: 2)` ×2）。
- 视频输出：暴露 `let player: AVPlayer` 给 VideoSurface 的 `AVPlayerLayer`。

### VLCBackend
- `VLCMediaPlayer()`，`delegate`（`VLCMediaPlayerDelegate`：`mediaPlayerStateChanged`、`mediaPlayerTimeChanged`）。
- 时间：`player.time.intValue`（毫秒），时长 `player.media?.length.intValue`。
- seek：`player.time = VLCTime(int: Int32(ms))`。
- 倍速：`player.rate = rate`。
- 音轨：`audioTrackIndexes` / `audioTrackNames`，`currentAudioTrackIndex`；字幕：`videoSubTitlesIndexes` / `videoSubTitlesNames`，`currentVideoSubTitleIndex`（-1 关闭）；外挂：`addPlaybackSlave(url, type: .subtitle, enforce: true)`；字幕延迟：`currentVideoSubTitleDelay`（微秒）。
- 视频输出：`player.drawable = uiView`（VideoSurface 提供的 UIView）。纯音频时 drawable 不设置。
- 选项：`VLCMedia` 添加 `:network-caching=1500`；本地文件 `:file-caching=300`。
- 硬件解码：VLC 3 在 iOS 默认 VideoToolbox，无需配置。
- 注意 VLC 回调不在主线程：在 delegate 中 `Task { @MainActor in ... }`。
- VLC 不支持系统画中画（PiP 仅 AV 后端可用；VLC 视频时 PiP 按钮显示为禁用，点击 toast `Picture in Picture isn't available for this format.`）。

### MediaSourceResolver
`func resolve(_ ref: MediaRef) async throws -> (MediaSource, PlaybackEngine)`：
- 本地：URL = 本地文件 URL。
- 远程：若已缓存 → 缓存 URL；否则若 `settings.streamRemoteMedia` 且非自签名 → 远程 URL + Authorization 头（AV）或带凭据的 URL（VLC）；否则下载到缓存（调用方显示 DownloadingView）。
- 引擎：`FileKind.engine(forExt:)`。

## 3. MediaRef 与播放队列模型
```swift
struct MediaRef: Codable, Hashable, Identifiable {
    var location: LocationID
    var path: String
    var name: String
    var id: String { location.key + ":" + path }
    init(_ item: FileItem)
}
struct TrackMetadata: Codable, Hashable { var title: String; var artist: String?; var album: String?; var duration: Double?; var artworkKey: String? }
```
MetadataLoader：
- 本地/缓存文件：`AVURLAsset.load(.commonMetadata, .duration)`，取 `.commonKeyTitle / .commonKeyArtist / .commonKeyAlbumName / .commonKeyArtwork`；AV 读不了的格式（ape/wma/ogg 等）用 `VLCMedia(url:)` + `parse(options: .parseLocal)` 读取 `metaData.title/artist/album/artworkURL`。
- 远程未缓存文件：先只用文件名（去扩展名）作为标题，开始播放后从播放器获得的元数据补全。
- 标题回退：文件名去扩展名；如果文件名形如 `01 - Artist - Title`，不做智能解析（保持简单）。
- 封面：存到 `Caches/Coffer/Artwork/<sha1>.jpg`（最长边 1024），`artworkKey` 为文件名。没有内嵌封面时，检查同目录 `cover.jpg / folder.jpg / front.jpg`（本地才检查）。
- 无封面占位：surfaceSunken 方块 + `music.note` 图标（inkTertiary，尺寸为方块的 35%）。

## 4. AudioPlayer
```swift
@MainActor @Observable final class AudioPlayer {
    enum RepeatMode: String, Codable { case off, all, one }
    private(set) var queue: [MediaRef] = []        // 当前播放顺序（随机时为打乱后的顺序）
    private var originalQueue: [MediaRef] = []     // 未打乱的顺序
    private(set) var index: Int = 0
    var current: MediaRef? { queue[safe: index] }
    private(set) var metadata: [String: TrackMetadata] = [:]
    private(set) var state: PlaybackState = .idle
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    var isPlaying: Bool
    var hasItem: Bool { current != nil }
    var rate: Float = 1.0            // 记住到 UserDefaults
    var repeatMode: RepeatMode = .off // 记住
    var shuffle = false               // 记住
    var sleepTimer: SleepTimer?       // .minutes(Date 截止) 或 .endOfTrack
    var sourceTitle: String?          // 队列来源，例如 "Music" 文件夹名、播放列表名，显示在全屏播放器顶部

    func play(_ refs: [MediaRef], startAt: Int, sourceTitle: String?)
    func togglePlayPause(); func next(); func previous()
    func seek(to: Double); func skip(by seconds: Double)
    func playNext(_ refs: [MediaRef]); func addToQueue(_ refs: [MediaRef])
    func remove(at offsets: IndexSet); func move(from: IndexSet, to: Int)
    func jump(to index: Int)
    func setShuffle(_ on: Bool)       // 打开：当前曲目保持在位置 0，其余随机；关闭：恢复 originalQueue 顺序并定位到当前曲目
    func cycleRepeat()                // off → all → one → off
    func stop()                       // 清空队列，迷你播放器消失
}
```
行为：
- `previous()`：currentTime > 3 秒 → 回到 0；否则上一首（index 0 且 repeat all → 最后一首）。
- 曲目结束：repeat one → seek 0 继续；否则 next；队尾且 repeat off → 停在最后一首开头暂停（不清空队列）。
- 睡眠定时：选项 `Off`、`15 min`、`30 min`、`45 min`、`1 hour`、`End of track`。到点后 3 秒内音量渐弱到 0 再暂停，然后恢复 volume = 1。
- 续播：每 5 秒保存 `(queue, index, currentTime)` 到 `positions.json` 中的 `lastSession`。冷启动时恢复队列和位置但**不自动播放**，迷你播放器显示暂停状态。
- 长音频（> 20 分钟，比如有声书/播客）：保存每个文件的播放位置（PlaybackPositionStore），下次播放同一文件时从该位置继续（剩余 < 10 秒视为已听完，从 0 开始）。
- 播放失败（文件不存在/格式错误）：toast `Couldn't play "<name>"`，自动跳到下一首；连续失败 3 首后停止。
- AV 后端失败时自动切 VLC 后端重试一次。

### NowPlayingCenter
- `MPNowPlayingInfoCenter.default().nowPlayingInfo`：title、artist、albumTitle、artwork（`MPMediaItemArtwork(boundsSize:requestHandler:)`）、`MPMediaItemPropertyPlaybackDuration`、`MPNowPlayingInfoPropertyElapsedPlaybackTime`、`MPNowPlayingInfoPropertyPlaybackRate`（暂停时 0）、`MPNowPlayingInfoPropertyDefaultPlaybackRate` = rate。在播放/暂停/seek/切歌/改倍速时更新（不要每 0.25s 更新）。
- `MPRemoteCommandCenter`：play、pause、togglePlayPause、nextTrack、previousTrack、changePlaybackPosition（拖动锁屏进度条）、changePlaybackRate（supportedPlaybackRates [0.5, 0.75, 1, 1.25, 1.5, 2]）、changeRepeatMode、changeShuffleMode。skipForward/skipBackward 不启用（与上一首下一首冲突）。
- 视频播放时，由 VideoPlayerModel 接管 NowPlaying（标题 = 文件名），关闭视频时清除并让 AudioPlayer 重新写入（若有音乐）。

## 5. 迷你播放器 MiniPlayerView（Tab 栏 accessory）
放在 `.tabViewBottomAccessory(isEnabled: player.hasItem)`。系统提供玻璃背景，不要加背景。
读取 `@Environment(\.tabViewBottomAccessoryPlacement) var placement`：

**expanded**（Tab 栏完整时，位于 Tab 栏上方的一条胶囊）：
```
[32×32 封面 圆角 6]  Song title                              [play/pause]  [forward.fill]
                     Artist
```
- 按钮只有两个：`play.fill/pause.fill`、`forward.fill`（下一首）。不放上一首（与 Apple Music 一致）。
- 标题 `.cofferCallout` 加粗单行，艺术家 caption inkSecondary 单行；无艺术家时显示 sourceTitle 或位置名。
- 背景上绘制一条极细进度线：在胶囊底部内侧，高 2pt，pink，宽度 = 进度（`.overlay(alignment: .bottomLeading)`，左右各内缩 16）。
**inline**（向下滚动 Tab 栏缩小后，accessory 与 Tab 栏同行）：
- 只显示 封面 24×24 + 标题（单行）+ play/pause 按钮。

交互：
- 点击（除按钮外的区域）→ 打开全屏音乐播放器（`player.isFullScreenPresented = true`）。封面作为 zoom 转场源：`.matchedTransitionSource(id: "nowPlaying", in: ns)`。
- 按钮点击区域 ≥ 44×44，按钮使用 `.buttonStyle(.plain)` + `.contentShape(.rect)`（系统 accessory 中按钮自带高亮）。
- 播放/暂停图标 `.contentTransition(.symbolEffect(.replace))`。
- 在 accessory 上左右滑动不切歌（避免误触）。
- 长按 → `.contextMenu`：`Show Queue`（打开全屏播放器并立即打开队列）、`Sleep Timer` 子菜单、`Stop Playback`（xmark.circle，清空队列，accessory 消失）。

## 6. 全屏音乐播放器 MusicPlayerView
`.fullScreenCover(isPresented: $player.isFullScreenPresented)`，`.navigationTransition(.zoom(sourceID: "nowPlaying", in: ns))`（iOS 18+ 在 fullScreenCover 内容上使用）。背景 canvas（不使用封面取色、不使用模糊、不使用渐变）。向下拖动关闭（zoom 转场自带交互式下滑关闭）。

竖屏布局（从上到下，左右 24 边距，全部居中）：
1. 顶部栏（高 44）：左 `chevron.down` 圆形玻璃按钮（关闭）；中间两行小字：`Playing from`（caption2 inkSecondary）+ sourceTitle（caption 加粗 ink），sourceTitle 为 nil 时整块隐藏；右 `ellipsis` 圆形玻璃按钮（Menu）。两按钮 `.buttonStyle(.glass)` `.buttonBorderShape(.circle)` `.controlSize(.large)`。
2. 弹性空隙。
3. 封面：正方形，宽 = min(屏宽 - 48, 360)，圆角 22，阴影（01 中唯一允许的阴影）。暂停时封面缩小到 0.86 倍，播放时 1.0（`.scaleEffect` + `.animation(.spring(duration: 0.45, bounce: 0.25), value: isPlaying)`）；减弱动态效果时不缩放。
   - 封面左右滑动切换上一首/下一首：`DragGesture`，水平位移 > 80 或速度足够时切换，封面跟手平移并回弹（`.offset(x:)`）。
4. 间距 28。
5. 标题行（HStack，左对齐，不居中）：左边 VStack 为标题（`.cofferTitle`，`.lineLimit(1)`，`.truncationMode(.tail)`）+ 艺术家（`.body` inkSecondary，单行）；右边是 **倍速按钮**：胶囊文字 `1x` / `1.5x`（`.cofferTimecode` 字号 subheadline，`.buttonStyle(.glass)`），点击弹出 `Menu`：0.5x、0.75x、1x、1.25x、1.5x、1.75x、2x、2.5x、3x（勾选当前）。
6. 间距 20。
7. Scrubber（进度条）：见 §8。下方两端时间：左已播放 `1:23`，右剩余 `-2:45`（`.cofferTimecode` inkSecondary）。
8. 间距 24。
9. 主控制行（三个纯图标按钮，`.buttonStyle(.plain)`，无玻璃）：`backward.fill`（上一首，32pt）、`play.fill/pause.fill`（48pt，ink 色）、`forward.fill`（下一首，32pt）。按钮间距 48。长按上一首/下一首 = 以 4 倍速快退/快进（按住期间每 0.25s seek ±2s，松开恢复）。点击时 `.symbolEffect(.bounce, value:)`。
10. 间距 24。
11. 次控制行（左右分布，图标 20pt，inkSecondary，开启态 pinkInk 并在下方显示 4pt 小圆点 pink）：
    `shuffle`（随机，开关）· `repeat` / `repeat.1`（循环：off 灰、all 粉、one 粉 + 图标 repeat.1）· `moon.zzz`（睡眠定时 Menu；激活时图标下显示剩余时间 `12:03` caption）· `list.bullet`（打开队列）· `AirPlay`（`AVRoutePickerView` 包装，tint ink，activeTint pinkInk）。
12. 底部安全区间距 12。

音量：不放音量条（使用实体按键；系统音量 HUD 正常显示）。

横屏（iPhone）：左边封面（高度 = 可用高度 - 40），右边从标题到次控制行的竖向栈。

右上 `ellipsis` Menu：`Add to Playlist…`、`Show in Files`（关闭全屏播放器并 reveal 文件所在文件夹，高亮该行）、`Get Info`、`Share`、Divider、`Skip Back 15 Seconds`、`Skip Forward 30 Seconds`、Divider、`Stop Playback`（destructive）。

## 7. 队列 QueueView
从全屏播放器 `list.bullet` 打开：`.sheet`，`.presentationDetents([.medium, .large])`。
- 顶部：当前曲目卡片（封面 48、标题、艺术家，背景 pinkSoft，圆角 14）。
- 段 `Up Next`（段标题右侧小按钮 `Clear`，清空当前之后的所有曲目）：`List` 中当前曲目之后的条目，支持拖动排序（`.onMove`，常显拖动把手：`.environment(\.editMode, .constant(.active))`）和左滑删除（`.onDelete`）。
- 段 `History`（之前已播放的，最多 20 条，inkSecondary，不可拖动）。点击任意条目 = `jump(to:)`。
- 顶部工具栏：shuffle 与 repeat 的开关按钮也放在此 sheet 的 toolbar 右侧（与全屏播放器状态同步）。

## 8. Scrubber（共用组件）
```swift
struct Scrubber: View {
    var current: Double; var duration: Double; var buffered: Double? = nil
    var onScrubbingChanged: (Bool) -> Void
    var onSeek: (Double) -> Void
    var style: Style = .music   // .music / .video
}
```
- 静止：轨道高 6（music）/ 4（video），Capsule；已播放部分 pink；缓冲部分 ink 15% 不透明；轨道 ink 10%（music 在 canvas 上）/ white 30%（video）。
- 按下即进入拖动态：轨道高度变为 12（music）/ 10（video），`.animation(.snappy)`，同时手指上方显示气泡时间 `1:23`（只显示时间，不做预览帧）。
- 拖动中不 seek，只更新显示；松手后 `onSeek`。拖动中左右时间标签跟随实时更新。
- 支持在轨道任意位置点击直接跳转。
- 精细拖动：手指在拖动时向上移动超过 60pt，拖动灵敏度降为 1/4（像 Apple Music），气泡显示 `Fine scrubbing`。
- 无障碍：`.accessibilityValue("1 minute 23 seconds of 4 minutes")`，`.accessibilityAdjustableAction` 增减 10 秒。

## 9. 视频播放器 VideoPlayerView
`fullScreenCover`，背景 `Color.black.ignoresSafeArea()`（这是唯一允许纯黑的地方），`.persistentSystemOverlays(.hidden)`（隐藏 Home 指示条），`.statusBarHidden(!controlsVisible)`，`preferredColorScheme(.dark)`。

### 9.1 VideoPlayerModel
```swift
@MainActor @Observable final class VideoPlayerModel {
    let playlist: [MediaRef]; var index: Int
    private(set) var backend: PlayerBackend
    var state, currentTime, duration, rate (默认 1，记住上次), isLooping (默认 false)
    var controlsVisible = true
    var isLocked = false           // 锁定：隐藏全部控制，只显示一个锁图标
    var videoGravity: Gravity = .fit   // .fit / .fill（双指捏合切换）
    var temporarySpeedBoost = false    // 长按倍速中
    var gestureHUD: GestureHUD?        // 当前显示的手势提示（seek / volume / brightness / speed）
    func togglePlay(); func seek(to:); func skip(by:)
    func next(); func previous()
    func close()
}
```
- 打开时：暂停 AudioPlayer；音频会话 mode `.moviePlayback`；从 PlaybackPositionStore 读取上次位置（> 30 秒且离结尾 > 30 秒时），**自动续播**并显示 toast 风格的小胶囊（左下角）`Resumed from 12:34 · Start Over`（点击 Start Over seek 0），4 秒后消失。
- 每 5 秒及关闭时保存播放位置。播放结束：清除位置记录；isLooping → seek 0 播放；否则若 playlist 中还有下一个 → 显示右下角卡片 `Up next: name  [Play]`，5 秒倒计时（圆环）后自动播放下一个，点 `Cancel` 取消；没有下一个 → 显示控制层并停在结尾。

### 9.2 画面层 VideoSurface
- AV：`UIView` 子类，`layerClass = AVPlayerLayer`，`videoGravity = .resizeAspect / .resizeAspectFill`（切换时 `CATransaction` 0.25s 动画）。
- VLC：普通 `UIView` 作为 drawable；`.fill` 时设置 `player.videoAspectRatio`/`scaleFactor`：使用 `player.scaleFactor = 0`（自动 fit）；fill 模式用 `player.videoCropGeometry` 设置为屏幕宽高比字符串（例如 `"19:9"`），fit 时设为 nil。

### 9.3 控制层布局（controlsVisible == true 时）
不加任何遮罩层。控件全部使用 `.glassEffect(.clear.interactive(), in: ...)` 或 `.glass` 按钮样式，保证在任何画面上可读；文字白色带 `.shadow(color: .black.opacity(0.6), radius: 3)`。

```
┌──────────────────────────────────────────────────────────────┐
│ (xmark)   Movie name.mkv                     (PiP) (AirPlay) (…) │  ← 顶部，安全区内 12pt
│           1080p · HEVC                                       │
│                                                              │
│ (lock)                                                       │  ← 左侧中部
│                (gobackward.10)  (  play  )  (goforward.10)    │  ← 正中，主按钮 72pt，两侧 52pt
│                                                              │
│                                                              │
│  12:34  ━━━━━━━━━━━━━●───────────────────  -1:02:11          │  ← 底部 Scrubber(.video)
│ (1x)  (repeat)  (captions)  (rotate)  (aspect)    (next)     │  ← 底部按钮行（胶囊/圆形玻璃）
└──────────────────────────────────────────────────────────────┘
```
- 顶部左：`xmark` 圆形玻璃按钮（关闭）。标题：文件名（headline 白色单行）+ 副标题（分辨率 · 编码，caption 白 70%，读不到就隐藏）。
- 顶部右：`pip.enter`（仅 AV 后端可用）、`AirPlay`（AVRoutePickerView，仅 AV 可用，VLC 隐藏）、`ellipsis` Menu（`Audio Track` 子菜单、`Subtitles` 子菜单（Off / 内置轨道 / `Add from Files…`）、`Subtitle Delay` 子菜单（-1.0s / -0.5s / -0.1s / Reset / +0.1s / +0.5s / +1.0s，显示当前值）、`Sleep Timer`、`Show in Files`、`Get Info`）。这三个按钮包在 `GlassEffectContainer` 中 HStack。
- 中部：`gobackward.10`、`play.fill/pause.fill`、`goforward.10`（快进快退步长可在设置中改 5/10/15/30 秒，图标随之 `gobackward.5` 等）。主按钮 `.glassEffect(.clear.interactive(), in: .circle)` 尺寸 72，图标 30pt 白；两侧 52/22pt。缓冲时主按钮图标替换为 `ProgressView().tint(.white)`。
- 左侧中部：`lock.open` 小圆按钮（44）。点击 → 锁定：隐藏所有控件，屏幕只剩同位置的 `lock.fill` 按钮（3 秒后也淡出，轻点屏幕再出现），锁定时所有手势失效（除了点击显示锁按钮）。再次点 `lock.fill` 解锁。
- 底部 Scrubber 上方左/右时间：`12:34` 与 `-1:02:11`（点击右侧时间可在“剩余时间/总时长”之间切换，记住）。
- 底部按钮行（左对齐一组 + 右对齐一组，全部在一个 GlassEffectContainer 内）：
  - `1x` 倍速胶囊（文字随当前倍速变化）→ Menu：0.25x、0.5x、0.75x、1x、1.25x、1.5x、2x、3x、4x（VLC 支持到 4x，AV 最多 2x 以上会无声，仍允许）。
  - `repeat`（循环当前视频开关，开启时图标 `repeat.1` + pink 着色玻璃 `.glassEffect(.clear.tint(.pink).interactive())`）
  - `captions.bubble`（字幕快速开关：有字幕轨道时在 Off 与上次轨道之间切换；无轨道时点击打开 `Add from Files…`）
  - `rotate.right`（旋转，见 9.6）
  - `rectangle.arrowtriangle.2.outward` / `rectangle.arrowtriangle.2.inward`（fit/fill 切换）
  - 右侧：`forward.end.fill`（下一个视频，playlist 中无下一个时隐藏）
- 控件自动隐藏：播放中 3.5 秒无操作后 `withAnimation(.smooth) { controlsVisible = false }`；暂停时不自动隐藏；打开 Menu 时不隐藏。

### 9.4 手势（在画面层上，控件层之下；控件可见时控件优先响应）
| 手势 | 行为 |
|---|---|
| 单击 | 切换 controlsVisible |
| 双击 左 1/3 区域 | 快退步长（默认 10s），在左侧显示涟漪圆 + `« 10s` 文字；连续双击累加（`« 20s`、`« 30s`），1 秒内无新点击后执行一次 seek |
| 双击 右 1/3 区域 | 快进步长，同上 `10s »` |
| 双击 中间区域 | 播放/暂停 |
| 长按（任意位置，0.4s） | 临时倍速：rate 变为 `settings.longPressSpeed`（默认 2x，可选 1.5/2/3）；顶部中央显示胶囊 `2x  ▶▶`（`forward.fill` 图标，`.glassEffect(.regular, in: .capsule)`）；松手恢复原倍速；触感 light。长按期间左右拖动可调节临时倍速（每 40pt 一档：1.5 / 2 / 2.5 / 3），胶囊文字实时变化 |
| 水平拖动（起始在中间 80% 高度区域） | 拖动 seek：每 1pt = 0.2 秒（总量不超过 ±时长），中央 HUD 显示 `+1:30` 与目标时间 `12:34 / 1:45:00`，以及一条细进度条；松手执行 seek。拖动开始时控件隐藏 |
| 垂直拖动 左半屏 | 亮度：`UIScreen.main.brightness`（通过 `windowScene.screen.brightness`）；左侧显示竖向 HUD 条 `sun.max.fill` + 进度条。关闭播放器时恢复原亮度 |
| 垂直拖动 右半屏 | 音量：通过隐藏的 `MPVolumeView` 中的 `UISlider` 设置系统音量（SystemVolume.swift）；右侧显示 `speaker.wave.2.fill` 竖向 HUD |
| 双指捏合 | 放大 → fill，缩小 → fit |
| 下滑（从顶部 1/4 开始的快速下滑） | 关闭播放器（等同 xmark） |
手势判定：使用一个自定义 `UIGestureRecognizer` 集合放在 UIKit 层（`VideoGestureView: UIView`，UITapGestureRecognizer(1 次) require(toFail: 2 次)、UILongPressGestureRecognizer、UIPanGestureRecognizer（在 began 时根据 velocity 判断方向锁定水平/垂直）、UIPinchGestureRecognizer），通过回调传给 model。**不要**用 SwiftUI 的 `TapGesture(count: 2)` + `TapGesture` 组合（会造成单击延迟且冲突）。单击需等待双击失败，所以单击有 ~0.25s 延迟，这是可接受的。

HUD 样式：居中圆角 18 的玻璃块 `.glassEffect(.regular, in: .rect(cornerRadius: 18))`，内边距 16，白色文字 `.cofferTimecode` 放大到 title3。出现/消失 `.opacity` + `.scale(0.9)`，`.snappy`。

### 9.5 画中画（PiPController，仅 AV 后端）
- `AVPictureInPictureController(contentSource: .init(playerLayer: layer))`，`canStartPictureInPictureAutomaticallyFromInline = true`（回到主屏幕时自动 PiP）。
- 点击 `pip.enter` → `startPictureInPicture()`，成功开始后**关闭 fullScreenCover 但保留 VideoPlayerModel 与 layer**（model 由 AppServices 中的 `activeVideo` 持有，layer 视图需要保持在窗口层级中：PiP 期间把 VideoSurface 移到 RootView 的一个 1×1 隐藏 overlay 里）。
- PiP 中点击“恢复”按钮（`restoreUserInterfaceForPictureInPictureStopWithCompletionHandler`）→ 重新 present 全屏播放器并把 surface 放回，然后 `completionHandler(true)`。
- PiP 结束（用户关闭小窗）→ 暂停并释放 model。
- 进入后台：AV 后端若正在播放且未 PiP，自动 PiP（系统处理）；若用户在设置中关闭 `Auto Picture in Picture`，则改为后台继续播放声音（`settings.backgroundVideoAudio`，默认开）：进入后台时把 `playerLayer.player = nil`（防止系统暂停），回前台时重新赋值。
- VLC 后端：后台继续播放声音（VLC 默认会继续解码；进入后台时 `player.drawable = nil` 不需要，保持即可），不支持 PiP。

### 9.6 旋转（OrientationController）
- App 整体支持竖屏 + 横屏（Info.plist 已声明），文件浏览界面跟随系统旋转，无需锁定。
- 视频播放器打开时：根据视频宽高比自动选择方向（`settings.autoRotateVideo` 默认开）：宽 > 高 → 请求横屏 `.landscapeRight`；否则竖屏。
  ```swift
  func request(_ mask: UIInterfaceOrientationMask) {
      AppDelegate.orientationLock = mask
      guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
      scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
      scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
  }
  ```
  `AppDelegate.application(_:supportedInterfaceOrientationsFor:)` 返回 `orientationLock`（默认 `.allButUpsideDown`）。
- 底部 `rotate.right` 按钮：在“锁定横屏 ↔ 锁定竖屏”之间切换（当前是横屏则请求 `.portrait`，反之 `.landscape`）。
- 打开播放器时记录当时的界面方向；关闭播放器时把 `orientationLock` 恢复为 `.allButUpsideDown`，若打开前是竖屏则再请求一次 `.portrait`。
- 横竖屏切换时控件层用 `.smooth` 动画重排（SwiftUI 自动）。

### 9.7 外挂字幕
- 打开视频时自动查找同目录同名字幕：`<base>.srt / .ass / .ssa / .vtt`，以及 `<base>.<lang>.srt`（本地直接找；远程在当前目录 listing 中查找并在需要时下载到缓存）。找到则自动加载（VLC 用 addPlaybackSlave，AV 用自渲染）。
- 字幕样式（AV 自渲染）：底部居中，距底 12% 高度（控件可见时上移到 Scrubber 上方），字号 = 视频高度的 5%（最小 16），白色 semibold，双层黑色阴影，最大宽度 85%。
- ASS/SSA 在 AV 后端：按 SRT 方式只取文本（去掉 `{\...}` 标签）。

## 10. 视频库 / 音乐库 / 播放列表
见 08 文档。
