# 01 · 设计系统

整体气质：像一本安静的纸质笔记本。暖米色纸面、深墨色文字、衬线标题、大量留白；系统 Liquid Glass 浮在纸面上；粉色只用于“当前/选中/主操作”，不要到处涂粉色。

## 1. 颜色 token
全部已在 `Assets.xcassets` 中定义（浅色/深色两套）。在 `Sources/Design/Theme.swift` 里写成 `Color` 扩展，视图只使用这些名字：

```swift
extension Color {
    static let canvas        = Color("Canvas")         // 页面背景（米黄纸色）
    static let surface       = Color("Surface")        // 卡片/分组行背景（比 canvas 稍亮）
    static let surfaceSunken = Color("SurfaceSunken")  // 输入框、代码块、缩略图占位底
    static let ink           = Color("Ink")            // 主文字/主图标
    static let inkSecondary  = Color("InkSecondary")   // 次要文字（大小、日期）
    static let inkTertiary   = Color("InkTertiary")    // 占位、禁用
    static let hairline      = Color("Hairline")       // 分隔线、描边
    static let pink          = Color("Pink")           // 品牌粉 sRGB(0.967, 0.743, 0.788) — 只做填充
    static let pinkInk       = Color("PinkInk")        // 可读的粉色文字/图标（浅色模式更深，深色模式即品牌粉）
    static let pinkSoft      = Color("PinkSoft")       // 选中行背景、进度条轨道
    static let onPink        = Color("OnPink")         // 粉色填充上的文字/图标（深墨色）
    static let danger        = Color("Danger")         // 删除等破坏性操作
    static let success       = Color("Success")        // 完成状态
}
```

| token | Light | Dark |
|---|---|---|
| Canvas | #F8F4E6 | #1A1916 |
| Surface | #FFFCF3 | #24221E |
| SurfaceSunken | #EFE9D8 | #2E2B26 |
| Ink | #2A2723 | #F3EFE4 |
| InkSecondary | #6E685D | #ABA597 |
| InkTertiary | #9C9587 | #7C776C |
| Hairline | #E3DCC8 | #3A3731 |
| Pink | sRGB 0.967/0.743/0.788 | 同左 |
| PinkInk | #A84860 | 同 Pink |
| PinkSoft | #F9DDE2 | #4A3238 |
| OnPink | #2A2723 | #2A2723 |
| Danger | #B83A2E | #FF8A7A |
| Success | #4E7D4A | #8FC08A |

使用规则：
- `AccentColor`（全局 tint）= PinkInk（浅）/ Pink（深）。在 App 根视图写 `.tint(.pinkInk)`。这样系统按钮文字、开关、选中态在浅色纸面上也看得清。
- 品牌粉 `Color.pink` 只用作“填充”：主按钮（`.glassProminent` 的 tint）、播放进度已播放段、选中勾选圆点、当前播放行左侧 3pt 竖条、徽标底色。粉色填充上的内容一律用 `.onPink`。
- 页面背景：每个顶层页面的 `List`/`ScrollView` 写 `.scrollContentBackground(.hidden)` + `.background(Color.canvas)`；非滚动页面用 `Color.canvas.ignoresSafeArea()` 作为最底层背景。
- `List` 分组行：`.listRowBackground(Color.surface)`；分隔线 `.listRowSeparatorTint(.hairline)`。
- 绝对禁止渐变。阴影只允许一种：`.shadow(color: .black.opacity(0.08), radius: 12, y: 4)`，用于封面图和浮动卡片。

## 2. 字体
标题用衬线（系统 New York），正文用系统无衬线。在 `Theme.swift` 写：

```swift
extension Font {
    static let cofferLargeTitle = Font.system(.largeTitle, design: .serif).weight(.semibold)
    static let cofferTitle      = Font.system(.title2, design: .serif).weight(.semibold)
    static let cofferHeadline   = Font.system(.headline, design: .serif)
    static let cofferBody       = Font.system(.body)
    static let cofferCallout    = Font.system(.callout)
    static let cofferCaption    = Font.system(.caption)
    static let cofferMono       = Font.system(.callout, design: .monospaced)
    static let cofferTimecode   = Font.system(.caption, design: .monospaced).monospacedDigit()
}
```

- 导航大标题：系统导航栏的大标题不能直接换字体，用以下方式统一换成衬线：在 `CofferApp.init()` 中设置
  ```swift
  let serif = UIFont.preferredFont(forTextStyle: .largeTitle).fontDescriptor.withDesign(.serif)!.withSymbolicTraits(.traitBold)!
  UINavigationBar.appearance().largeTitleTextAttributes = [.font: UIFont(descriptor: serif, size: 0)]
  let serifInline = UIFont.preferredFont(forTextStyle: .headline).fontDescriptor.withDesign(.serif)!
  UINavigationBar.appearance().titleTextAttributes = [.font: UIFont(descriptor: serifInline, size: 0)]
  ```
  只设置字体属性，不要设置背景、不要 `configureWithOpaqueBackground`。
- 文件名：`.cofferBody`，单行，`.truncationMode(.middle)`（保证后缀名可见，例如 `Very long name…final.mp4`）。
- 文件元信息（大小 · 日期）：`.cofferCaption` + `.inkSecondary`，数字 `.monospacedDigit()`。
- 所有时间码（播放进度、剩余时间、速度）用 `.cofferTimecode`。
- 支持动态字体：不写死字号（上面已经全部基于 text style）。

## 3. 间距与形状
- 网格基数 4pt：常用 4 / 8 / 12 / 16 / 20 / 24 / 32。
- 页面左右内边距 20。
- 圆角：小 8（缩略图）、中 14（卡片、输入框）、大 22（大卡片、封面）、胶囊 `Capsule()`（标签、小按钮）。全部用 `RoundedRectangle(cornerRadius: r, style: .continuous)`。
- 列表行最小高度 56（带图标的文件行）；网格视图单元 104×(104+40)。
- 点击区域最小 44×44。

## 4. Liquid Glass 用法（务必遵守）
系统自动玻璃：`NavigationStack` 的导航栏与 `.toolbar` 按钮、`TabView` 的 Tab 栏、`.tabViewBottomAccessory`、`.searchable` 搜索框、`Menu`、`.sheet`（半屏时自动玻璃）。这些不要加任何背景。

需要手动用玻璃的地方（只有这些）：
| 位置 | 写法 |
|---|---|
| 浮动操作按钮/胶囊（例如选择模式底部操作条、粘贴条、视频播放器控制按钮组） | `GlassEffectContainer(spacing: 12) { HStack { ... 每个按钮 .glassEffect(.regular.interactive(), in: .capsule) } }` |
| 主要行动按钮（例如 Connect、Save、Start） | `.buttonStyle(.glassProminent)` + `.tint(.pink)`，按钮 label 前景 `.onPink` |
| 次要按钮 | `.buttonStyle(.glass)` |
| 视频播放器上的控制按钮 | `.glassEffect(.clear.interactive(), in: .circle)`（视频画面上用 clear 变体） |
| 视频播放器里的倍速提示 “2x” 浮层 | `.glassEffect(.regular, in: .capsule)` |

- 多个相邻玻璃元素必须包在同一个 `GlassEffectContainer` 里，这样它们会融合/形变。
- 出现/消失的玻璃元素用 `@Namespace` + `.glassEffectID(id, in: ns)`，配合 `withAnimation(.smooth)` 产生液态形变。
- 不要在玻璃上叠 `.background(...)`。

## 5. 动画
- 统一使用 `.smooth`（默认）和 `.snappy`（小控件切换），时长都用系统默认，不要写 `.easeInOut(duration:)` 这种僵硬曲线，不要用 `.linear`（进度条除外）。
- 列表增删：`withAnimation(.smooth) { ... }`，List 会自动做行插入/删除动画。
- 选中/勾选：`.contentTransition(.symbolEffect(.replace))` 切换 `circle` ↔ `checkmark.circle.fill`。
- 播放/暂停图标：`Image(systemName: isPlaying ? "pause.fill" : "play.fill").contentTransition(.symbolEffect(.replace))`。
- 数字变化（进度百分比、速度）：`.contentTransition(.numericText())`，并在 `withAnimation` 中修改值。
- 打开文件预览：使用 zoom 转场。文件行 `.matchedTransitionSource(id: item.id, in: ns)`，目标视图 `.navigationTransition(.zoom(sourceID: item.id, in: ns))`。
- 迷你播放器 → 全屏播放器：`.fullScreenCover` + `.navigationTransition(.zoom(sourceID: "nowPlaying", in: ns))`，源是迷你播放器的封面。
- 触感：成功操作 `.sensoryFeedback(.success, trigger:)`；进入选择模式/长按倍速 `.sensoryFeedback(.impact(weight: .light), trigger:)`；删除 `.sensoryFeedback(.warning, trigger:)`。
- 尊重“减弱动态效果”：`@Environment(\.accessibilityReduceMotion)` 为 true 时，zoom 转场照常（系统处理），自定义的 scale/offset 动画改为直接切换。

## 6. 图标
### App 图标（已完成）
`Assets.xcassets/AppIcon.appiconset` 已含 1024px 浅色/深色/着色三张。造型：一只扁平的小宝箱（Coffer 本意就是“保险箱/宝箱”），墨色箱盖 + 粉色箱体 + 米色锁扣。源文件在 `docs/icon/*.svg`。不要修改。

### 应用内图形
- `Image("CofferGlyph")`：宝箱单色模板图（template 渲染），用于首页空状态、关于页、设置页头部。用 `.foregroundStyle(.pinkInk)`。
- 其余全部用 SF Symbols，统一 `.symbolRenderingMode(.hierarchical)`，不要彩色多色模式。

### 文件类型图标映射（`FileKind` → SF Symbol + 色块）
文件行左侧是 40×40 圆角 8 的方块：底色 `surfaceSunken`，中间是 SF Symbol（20pt，`.ink` 着色）。如果能生成缩略图（图片、视频、PDF），用缩略图替换整个方块（`.aspectRatio(contentMode: .fill)` 裁切，圆角 8，0.5pt `hairline` 描边）。

| FileKind | 扩展名 | SF Symbol |
|---|---|---|
| folder | 目录 | `folder.fill`（唯一例外：色块底色用 `pinkSoft`，图标 `.pinkInk`） |
| image | jpg jpeg png heic heif gif webp bmp tiff tif svg ico raw dng cr2 nef arw | `photo` |
| video | mp4 m4v mov mkv avi flv wmv webm ts m2ts mts 3gp rm rmvb mpg mpeg vob ogv f4v asf divx | `film` |
| audio | mp3 m4a aac wav aiff aif flac alac ogg oga opus wma ape caf amr m4b mka dsf dff wv tta mid midi | `waveform` |
| pdf | pdf | `doc.richtext` |
| markdown | md markdown mdown mkd | `text.document` |
| html | html htm xhtml | `chevron.left.forwardslash.chevron.right` |
| code | swift js mjs ts tsx jsx py rb go rs java kt kts c h cpp hpp cc m mm cs php sh bash zsh fish ps1 lua pl r sql css scss less vue dart scala hs ex exs clj gradle cmake makefile dockerfile | `curlybraces` |
| data | json yaml yml toml xml plist csv tsv ini conf cfg env properties log | `list.bullet.rectangle` |
| text | txt text rtf* srt ass ssa vtt lrc nfo readme license 以及无扩展名的纯文本 | `doc.plaintext` |
| office | doc docx xls xlsx ppt pptx pages numbers key odt ods odp rtf | `doc.text` |
| archive | zip rar 7z tar gz tgz bz2 xz | `archivebox` |
| ebook | epub mobi azw3 | `book.closed` |
| font | ttf otf woff woff2 | `textformat` |
| package | ipa apk dmg pkg deb | `shippingbox` |
| unknown | 其他 | `doc` |

（*rtf 归 office，由 QuickLook 渲染。）

## 7. 文案语气
英文、简短、句首大写（Sentence case），不要感叹号，不要全大写按钮。示例：
- 空文件夹：标题 `This folder is empty`，副标题 `Tap + to add files or create a folder.`
- 删除确认：`Delete 3 items?` / 说明 `This can't be undone.` / 按钮 `Delete` `Cancel`
- WebDAV 连接失败：`Couldn't connect to the server` + 下方显示具体原因（HTTP 状态码或 `error.localizedDescription`）。
- 传输完成：`Downloaded` / `Uploaded`；失败：`Failed. Tap to retry.`

## 8. 空状态与加载
- 空状态：用 `ContentUnavailableView { Label(title, systemImage:) } description: { Text(...) } actions: { Button(...) }`，图标颜色 `.inkTertiary`。
- 加载：远程目录首次加载时在列表中央 `ProgressView()`；已有缓存时先显示缓存内容，同时在导航栏标题下用 `.navigationSubtitle("Updating…")` 提示，完成后移除。
- 下拉刷新：`.refreshable { await model.reload(force: true) }`。
