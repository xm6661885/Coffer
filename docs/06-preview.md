# 06 · 文件预览

## 1. PreviewRouter
输入 `PreviewRoute(item, siblings)`。
1. 若 `item.location.isRemote` 且该类型需要本地文件（除了音视频流式播放之外的全部类型）：
   - 已缓存 → 直接用缓存 URL。
   - 未缓存 → 显示 `DownloadingView`（居中：FileIconView 64pt、文件名、ProgressBar（宽 220）、`1.2 MB of 8.4 MB`、按钮 `Cancel`（返回上一页并取消任务））。完成后 `withAnimation(.smooth)` 切换到预览内容。
2. 按 `item.kind` 选择视图：

| kind | 视图 |
|---|---|
| image | ImagePreview（siblings 里的图片可左右滑动翻页） |
| pdf | PDFPreview |
| markdown | TextPreview(mode: .markdown) |
| html | TextPreview(mode: .html) |
| code / data / text | TextPreview(mode: .code / .data / .plain) |
| office / ebook(epub) | QuickLookPreview |
| archive(zip) | ArchivePreview；其他压缩格式 → UnsupportedPreview |
| font | FontPreview |
| audio / video | 不会进入 PreviewRouter（BrowserView 直接播放），保险起见：audio → 调用播放并 pop；video → 打开视频播放器并 pop |
| unknown | 先尝试 QuickLook（`QLPreviewController.canPreview(url)`），能则 QuickLook；否则若前 4KB 能按 UTF-8 解码且不含 NUL → TextPreview(.plain)；否则 UnsupportedPreview |

3. 打开时 `recents.add(item)`。

### 预览页公共导航栏
- 标题 = 文件名（inline，`.toolbarTitleDisplayMode(.inline)`），`navigationSubtitle` = 大小 · 修改日期。
- 右上：`ShareLink`/Share 按钮（square.and.arrow.up）+ `Menu`（ellipsis.circle）：`Open in…`（UIDocumentInteractionController 的“打开方式”菜单）、`Rename`、`Get Info`、`Delete`（删除后 pop）、文本类额外 `Edit`。
- 预览页隐藏 Tab 栏：`.toolbar(.hidden, for: .tabBar)`。
- 图片/PDF 预览：单击内容切换“沉浸模式”：隐藏导航栏（`.toolbarVisibility(immersive ? .hidden : .visible, for: .navigationBar)`）和状态栏（`.statusBarHidden(immersive)`），背景保持 canvas（不要变黑），用 `withAnimation(.smooth)` 切换。

## 2. TextPreview（文本 / Markdown / HTML / 代码 / 数据）
- markdown / html / csv / tsv / json：有两种显示方式 `Rendered` 和 `Source`。在导航栏 `ToolbarItem(placement: .principal)` 放 `Picker("", selection: $mode) { Text("Rendered").tag(...); Text("Source").tag(...) }.pickerStyle(.segmented).fixedSize()`。此时文件名显示在 `navigationSubtitle`（不再显示大小）。默认 Rendered；用户的选择按扩展名记住（UserDefaults `previewMode.<ext>`）。
- 其他文本（txt、代码、log 等）：只有 Source（带语法高亮），不显示分段控件，标题为文件名。

### Source 模式
用 `WebRenderView` 渲染，原因：大文件下 WKWebView 性能稳定，并且可以统一使用 highlight.js。
- HTML 模板（Swift 字符串常量 `SourceTemplate`），内联 CSS：
  - `body { margin:0; background: var(--canvas); color: var(--ink); }`
  - `pre { margin:0; padding: 16px 20px 40px; font: 13px/1.55 ui-monospace, Menlo, monospace; white-space: pre; tab-size: 4; }` ；软换行开启时 `white-space: pre-wrap; word-break: break-word;`
  - 行号：用 CSS counter，每行包 `<span class="l">`，`.l::before { counter-increment: line; content: counter(line); display:inline-block; width: 3.5em; margin-right: 1em; text-align:right; color: var(--ink3); user-select:none; }`
  - CSS 变量 `--canvas --surface --ink --ink2 --ink3 --pink --hairline` 由 Swift 根据当前 colorScheme 注入（把 token 的十六进制值写进 `<style>:root{...}</style>`），深色模式切换时重新加载页面。
  - highlight.js 主题：自己写一份极简 token 配色（不要引用外部主题文件）：`.hljs-keyword,.hljs-selector-tag{color:var(--pinkInk)}` `.hljs-string{color:#4E7D4A}`（深色 #8FC08A）`.hljs-comment{color:var(--ink3);font-style:italic}` `.hljs-number,.hljs-literal{color:#9A6B1F}`（深色 #E0B570）`.hljs-title,.hljs-function{color:var(--ink);font-weight:600}` 其余默认 ink。
- 处理流程：
  1. Swift 侧用 TextDecoding 解码文件得到 String。
  2. 把文本以 JSON 字符串形式注入模板（`JSONEncoder().encode(text)`，避免手动转义），在 JS 中写入 `<code>` 的 `textContent`。
  3. 文件 < 1 MB 且语言已知时，JS 调用 `hljs.highlightElement(codeEl)`（整段高亮，不要逐行高亮）。语言按扩展名映射：swift, javascript, typescript, python, ruby, go, rust, java, kotlin, c, cpp, objectivec, csharp, php, bash, lua, perl, r, sql, css, scss, less, xml, html, json, yaml, ini, markdown, dockerfile, makefile；未知用 plaintext（不高亮）。
  4. 行号：布局为 `<div class="wrap" style="display:grid; grid-template-columns:auto 1fr">`，左列 `<pre class="gutter">` 放 `1\n2\n3…`（JS 按行数生成，颜色 ink3，右对齐，不可选中），右列 `<pre><code>`。两列字体与行高完全相同，因此逐行对齐。
  5. 软换行开启时隐藏行号列（换行后无法对齐）。
- 大文件：> 5 MB 只显示前 5 MB，顶部提示条 `Showing the first 5 MB.`；> 1 MB 时不做高亮。
- 工具栏（右上 Menu 中额外项）：`Wrap Lines` Toggle（默认开，全局记住）、`Text Size` 子菜单（Smaller / Default / Larger，影响 font-size 11/13/16）、`Encoding` 子菜单（Auto、UTF-8、UTF-16、GB18030、Big5、Shift_JIS、EUC-KR、Windows-1252、ISO-8859-1；选中后重新解码）。
- 查找：右上增加 `magnifyingglass` 按钮，点击后使用 WKWebView 的 `isFindInteractionEnabled = true` 并调用 `webView.findInteraction?.presentFindNavigator(showingReplace: false)`（系统查找条，Liquid Glass 原生）。

### Rendered 模式
- Markdown：模板中加载 `marked.umd.js`、`purify.min.js`、`highlight.min.js`（通过 `loadHTMLString(html, baseURL: Bundle.main.resourceURL)`，`<script src="marked.umd.js">`）。渲染：`document.getElementById('c').innerHTML = DOMPurify.sanitize(marked.parse(src, {gfm:true, breaks:false}))`，然后对 `pre code` 执行 hljs。markdown 源文本以 JSON 字符串形式注入（`JSONEncoder` 编码 String，避免转义问题）。
  - 样式（文章排版，模仿 Anthropic 文档风格）：正文 `-apple-system`，17px/1.65，最大宽度 720px 居中，左右内边距 20px；h1/h2/h3 用 `ui-serif, "New York", Georgia, serif`，字重 600，h1 30px、h2 24px（下边框 1px hairline，padding-bottom 6px）、h3 20px；链接 pinkInk 无下划线（hover 无意义）；`code` 行内：surfaceSunken 背景、圆角 6、padding 2px 5px、13px 等宽；`pre`：surfaceSunken 背景、圆角 12、padding 14px 16px、横向滚动；`blockquote`：左边 3px pink 竖线、padding-left 14px、颜色 ink2；表格：边框 hairline，表头 surfaceSunken；`img` 最大宽 100%，圆角 10；`hr`：1px hairline；任务列表 checkbox 用 `accent-color: var(--pink)`。
  - 相对路径图片：在 Swift 侧预处理 markdown 源文本：用正则找出 `![alt](path)` 与 `<img src="path">` 中的非 http(s)、非 data: 路径，相对于该 markdown 文件所在目录解析；若对应本地文件存在（本地位置或远程缓存目录）且 ≤ 10 MB，则读入并替换为 `data:<mime>;base64,...`。远程 markdown 中的相对图片不额外下载（显示为破图即可）。然后统一 `loadHTMLString(html, baseURL: Bundle.main.resourceURL)`。
  - 链接点击：`WKNavigationDelegate.decidePolicyFor`：`http/https` → 用 `SFSafariViewController` 打开（`.sheet`）；`#anchor` → 允许；其余取消。
- HTML：Rendered = 直接加载该 HTML 文件。本地文件用 `loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())`（这样同目录的 css/js/图片都能加载）；远程文件用缓存 URL 同样处理（仅单文件可用，相对资源大概率缺失，可接受）。允许 JavaScript。外链点击同上。
- CSV/TSV：Rendered = 表格。Swift 侧解析（支持引号包裹、双引号转义、字段内换行），最多显示前 2000 行，生成 `<table>`，首行作为表头 `position: sticky; top:0`，奇数行背景 surface，等宽数字。超过时底部提示 `Showing 2,000 of 15,320 rows.`。
- JSON：Rendered = 用 `JSONSerialization.jsonObject` 解析后以 `JSONSerialization.data(withJSONObject:, options: [.prettyPrinted, .withoutEscapingSlashes, .fragmentsAllowed])` 重新格式化，再按 json 语言高亮显示；解析失败则显示 `This file isn't valid JSON.` 提示条 + 原文。

### WebRenderView
```swift
struct WebRenderView: UIViewRepresentable {
    enum Content: Equatable { case html(String, baseURL: URL?), file(URL, readAccess: URL) }
    let content: Content
    var findEnabled = true
    @Binding var webView: WKWebView?   // 外部用来调用查找
}
```
- `WKWebViewConfiguration`：`defaultWebpagePreferences.allowsContentJavaScript = true`；`dataDetectorTypes = []`。
- `webView.isOpaque = false; webView.backgroundColor = .clear; scrollView.backgroundColor = .clear`，外层 SwiftUI 背景 canvas，避免白闪。
- `scrollView.contentInsetAdjustmentBehavior = .automatic`（让内容从导航栏下方开始，同时滚动到导航栏下有玻璃效果）。
- 仅当 `content` 变化时重新加载（Coordinator 记录上次内容）。

### TextDecoding
```swift
enum TextDecoding {
    static func decode(_ data: Data, preferred: String.Encoding? = nil) -> (text: String, encoding: String.Encoding)
}
```
顺序：preferred → BOM 检测（UTF-8 BOM、UTF-16 LE/BE）→ 严格 UTF-8 → `NSString.stringEncoding(for:encodingOptions:convertedString:usedLossyConversion:)`，其中 `suggestedEncodingsKey` 给 `[GB18030, Big5, ShiftJIS, EUC-KR, windowsCP1252]`，`useOnlySuggestedEncodingsKey: false`，`allowLossyKey: false` → 最后回退 `String(decoding: data, as: UTF8.self)`（有替换符）。GB18030 的 `String.Encoding`：`String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))`。

## 3. ImagePreview
- `TabView(selection: $currentID) { ForEach(imageSiblings) { ZoomableImage(item) .tag(id) } }.tabViewStyle(.page(indexDisplayMode: .never))`。
- `ZoomableImage`：`UIScrollView` 包装（UIViewRepresentable）：`minimumZoomScale = 1`，`maximumZoomScale = 6`，图片按 aspect-fit 居中；双击：未放大时放大到 2.5 倍并以点击点为中心，已放大时恢复 1 倍（`zoom(to:animated:)`）。
- 解码：使用 `UIImage(contentsOfFile:)` 后 `preparingForDisplay()`（后台）；大图（> 40MP）用 `CGImageSourceCreateThumbnailAtIndex` 下采样到屏幕 3 倍尺寸。GIF：用 `CGImageSource` 读取所有帧生成 `UIImage.animatedImage(with:duration:)`。WebP/HEIC 系统原生支持。SVG：用 WebRenderView 渲染（`<img src="data:image/svg+xml;base64,...">` 居中）。RAW（dng/cr2/nef/arw）：`CIRAWFilter` 渲染为 CGImage。
- 导航栏标题随翻页更新为当前图片名；底部（沉浸模式关闭时）显示 `3 of 24` caption。
- 远程图片翻页：相邻图片在需要时通过 RemoteCache 下载，未下载时显示 ProgressView。
- 下滑关闭：不实现（使用系统返回）。

## 4. PDFPreview
- `PDFView`（UIViewRepresentable）：`autoScales = true`，`displayMode = .singlePageContinuous`，`displayDirection = .vertical`，`usePageViewController(false)`，背景 `UIColor(named: "Canvas")`，`pageShadowsEnabled = true`。
- 右上额外按钮：`magnifyingglass`（PDFView 内置 `isFindInteractionEnabled = true` 并 present find navigator）、Menu 中 `Single Page / Continuous` 切换、`Go to Page…`（alert 输入页码，这里允许 alert）。
- 底部浮动页码胶囊 `12 / 140`（`.glassEffect(.regular, in: .capsule)`），滚动时显示，停止 1.5 秒后淡出。监听 `.PDFViewPageChanged`。
- 记住每个 PDF 的阅读页（PlaybackPositionStore 复用，key = item.id，值 = 页码）。

## 5. QuickLookPreview
- `QLPreviewController` 包装为 `UIViewControllerRepresentable`（直接返回 QLPreviewController 实例），dataSource 返回单个 `url as NSURL`。它作为我们导航页的内容嵌入显示（不要 present 系统的全屏 QL）。QL 内部自带的分享/标注按钮若出现，保留即可，不要尝试 hack 隐藏。
- 适用：doc/docx/xls/xlsx/ppt/pptx/pages/numbers/key/rtf/epub（iOS 26 QL 可预览 epub 首页；不可时 UnsupportedPreview）/usdz/其它 QL 支持的类型。

## 6. ArchivePreview（zip）
- 使用 ZIPFoundation `Archive(url:, accessMode: .read)` 枚举条目，构建树结构，界面是可钻取的 List（文件夹 → 下一级），行显示名称、未压缩大小。
- 顶部 `.safeAreaInset(edge: .top)` 信息条：`24 items · 18.2 MB uncompressed`。
- 底部 `.safeAreaInset(edge: .bottom)` 大按钮 `Uncompress`（glassProminent pink）：解压到同目录下的 `<zipname>/` 文件夹（已存在则 `<zipname> 2`），远程 zip 则解压到 `My iPhone/<zipname>/`。解压进度 ProgressBar（按条目数）。完成后 toast `Uncompressed to "<folder>"`，动作 `Show`。
- 点击条目：解压单个条目到 tmp 后用 PreviewRouter 预览（push）。
- 编码：中文 Windows 打包的 zip 文件名可能是 GBK：若条目路径包含替换字符 `\u{FFFD}`，尝试用 `Archive(url:, accessMode:, pathEncoding: .init(gb18030))`（ZIPFoundation 支持 pathEncoding 参数）重新打开。

## 7. Compress（本地）
`ZipService.compress(items: [URL], into dir: URL, name: String)`：单项 → `<name>.zip`；多项 → `Archive.zip`（冲突加数字）。使用 `FileManager.zipItem(at:to:shouldKeepParent: true, compressionMethod: .deflate, progress:)`；多项时先创建 tmp 目录放硬链接/拷贝再压缩。显示 toast `Compressing…`（带进度），完成 `Created "Archive.zip"`。

## 8. FontPreview
`CTFontManagerCreateFontDescriptorsFromURL` → `UIFont(descriptor:size:)`。显示：字体全名（cofferTitle）、样张 “The quick brown fox jumps over the lazy dog” 在 16/24/36/56 pt，字符集一段 `ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789`，以及中文样张 `永和九年，岁在癸丑` 若字体包含这些字形。

## 9. UnsupportedPreview
`ContentUnavailableView { Label("No preview available", systemImage: item.kind.symbol) } description: { Text("\(Kind) · \(size)") } actions: { Button("Open in…") {…}.buttonStyle(.glassProminent); Button("Open as Text") {…}.buttonStyle(.glass) }`。`Open as Text` 强制 TextPreview(.plain)。

## 10. 缩略图 ThumbnailService
- `QLThumbnailGenerator.shared.generateBestRepresentation(for: .init(fileAt: url, size: CGSize(width: 80, height: 80), scale: displayScale, representationTypes: .thumbnail))`。
- 仅为 image / video / pdf / font 生成，其他类型使用图标（加速）。
- 内存缓存 `NSCache<NSString, UIImage>`（countLimit 500），磁盘缓存 `Caches/Coffer/Thumbnails/<sha256(item.id + modified)>.jpg`。
- 远程文件：仅当已缓存到本地时生成；否则显示类型图标（不要为了缩略图下载大文件）。图片类远程文件小于 5 MB 时允许后台下载生成缩略图（设置项 `Load thumbnails for remote images`，默认开）。
- `FileIconView` 中 `.task(id: item.id) { image = await thumbnails.thumbnail(for: item) }`，出现时 `.transition(.opacity)`。
