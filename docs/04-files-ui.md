# 04 · 界面骨架与文件浏览交互

> 写给实现者：本文件描述的是“用户手指在屏幕上做什么 → 看到什么”。请严格按照这里的层级、位置、文案实现。凡是本文没有提到的控件就不要加；凡是本文提到的手势/菜单都必须有。设计原则：**一切行为与 iOS 自带“文件”App 保持一致**；拿不准时，模仿“文件”App 和“设置”App 的做法，而不是自创。

## 0. 反面清单（以下做法一律禁止）
- 禁止在屏幕上放一排按钮代替菜单（例如在每一行右边放“重命名/删除/分享”三个按钮）。行级操作只通过 长按菜单 和 左滑 完成。
- 禁止弹 `.alert` 去做输入以外的选择（选择用 `.confirmationDialog` 或 `Menu`）。
- 禁止自定义返回按钮。返回上一级 = 系统导航栏返回按钮 + 系统边缘右滑手势（NavigationStack 自带，不要禁用）。
- 禁止操作完成后弹 alert 说“成功”。成功用 Toast 或静默；失败用 Toast。
- 禁止把“返回上一级”做成列表第一行 “..”。
- 禁止在任何时候出现无法退出的状态：每个 sheet 都有 Cancel/Done；选择模式工具栏右上角永远有 `Done`。
- 禁止阻塞主线程（所有 IO async）。列表加载时不要整页白屏，保留旧内容。
- 禁止固定写死设备尺寸，iPhone 横屏、iPad 也要可用。

## 1. 根结构 RootView
```swift
TabView(selection: $tab) {
    Tab("Files", systemImage: "folder", value: AppTab.files) { FilesRoot() }
    Tab("Tools", systemImage: "square.grid.2x2", value: AppTab.tools) { ToolsView() }
}
.tabBarMinimizeBehavior(.onScrollDown)
.tabViewBottomAccessory(isEnabled: player.hasItem) { MiniPlayerView() }
```
- 只有两个 Tab，Tab 栏为系统 Liquid Glass，不加背景。
- 向下滚动时 Tab 栏自动缩小（系统行为），迷你播放器随之变成 inline 模式（见 07）。
- `FilesRoot` = `NavigationStack(path: $filesPath) { HomeView().navigationDestination(for: BrowserRoute.self) { BrowserView(route: $0) } .navigationDestination(for: PreviewRoute.self) { PreviewRouter(route: $0) } }`。
  ```swift
  struct BrowserRoute: Hashable { let location: LocationID; let path: String }
  struct PreviewRoute: Hashable { let item: FileItem; let siblings: [FileItem] }  // siblings 用于图片左右翻页、音乐“播放此文件夹”
  ```
- `filesPath` 放在一个 `@Observable final class Navigator`（RootView 持有并注入），这样 Toast 的 “Show”、导入完成等可以编程跳转：`navigator.reveal(location:, path:)` = 切到 Files Tab，把 `filesPath` 设为从根到该路径的每一级 `BrowserRoute`。
- 再次点击当前已选中的 Files Tab 图标：返回首页（`filesPath.removeAll()`）。实现：用自定义 `Binding` 包装 `tab`，setter 中若新值 == 旧值 == .files，则清空路径。
- RootView 还挂载：Toast overlay、`FileOperations.conflict` 的 confirmationDialog、导入 sheet、传输面板 sheet（`navigator.showTransfers`）、全屏音乐播放器 `.fullScreenCover`、全屏视频播放器 `.fullScreenCover`。

## 2. 首页 HomeView（Files Tab 根）
导航标题 `Coffer`，大标题模式（`.navigationBarTitleDisplayMode(.large)`）。
使用 `List`（`.listStyle(.insetGrouped)`），背景 canvas，行背景 surface。

### 段 1：Locations（无段标题）
第一行 **My iPhone**：
```
[40×40 色块 iphone 图标]  My iPhone                       >
                         38.2 GB available
```
- 色块：底 `pinkSoft`，图标 `iphone`，`.pinkInk`。
- 副标题：可用空间（`ByteCountFormatter`，`.file` 风格）。
- 点击 → push `BrowserRoute(location: .local, path: "/")`。

### 段 2：WebDAV（段标题 `WebDAV`）
每个服务器一行：
```
[色块 server.rack]  Home NAS                               >
                    nas.local · admin
```
- 副标题：`host · username`（无用户名则只 host）。
- 若最近一次连接失败，副标题后面加 ` · Offline`，颜色 `danger`。
- 点击 → push `BrowserRoute(location: .webdav(id), path: server.initialPath)`（initialPath 默认 "/"）。
- 长按菜单：`Edit`（pencil）、`Copy URL`（doc.on.doc）、`Disconnect & Remove`（trash，destructive，二次确认 `Remove "Home NAS"?` / `Downloaded files stay on your iPhone.`）。
- 左滑：`Remove`（destructive，同样二次确认）。
- 段最后一行固定为按钮行 `Add WebDAV Server`（`plus.circle` 图标，`.pinkInk` 文字）→ `.sheet` 打开 `AddServerView`。
- 拖动排序：`.onMove`（List 在非编辑态也支持长按拖动，iOS 16+）。

### 段 3：Recents（段标题 `Recents`，无记录时整段隐藏）
最近打开的 5 个文件（RecentsStore，最多存 50）。行 = FileRow 简版（图标+名称+所在位置名）。点击直接打开预览。段尾 `Show All`（推入一个完整 Recents 列表页，右上 `Clear` 清空）。

### 工具栏
- 右上：`Menu`（`ellipsis.circle`）：`Transfers`（arrow.up.arrow.down，有活动任务时右侧显示数字）、`Settings`（gear）。
- 当传输队列中有活动任务时，导航栏右上在 Menu 左边额外出现一个圆形进度按钮（`TransferIndicator`）：直径 28 的圆环（轨道 hairline，进度 pink，线宽 3），中心 `arrow.down` 小图标；点击打开传输面板。用 `ToolbarItem(placement: .topBarTrailing)`。

### 空状态
没有 WebDAV 服务器时，段 2 只有 `Add WebDAV Server` 一行，下方段脚注 `Connect a NAS, a cloud drive or any WebDAV server.`。

## 3. 添加/编辑服务器 AddServerView
`.sheet`，`NavigationStack` + `Form`，标题 `New Server` / `Edit Server`（inline）。
左上 `Cancel`，右上 `Save`（未填 URL 时禁用）。

Form 内容：
- 段 1：
  - `Name` TextField（placeholder `Home NAS`，留空则保存时用 host）。
  - `URL` TextField（placeholder `https://example.com/dav`，`.keyboardType(.URL)`，`.textInputAutocapitalization(.never)`，`.autocorrectionDisabled()`）。用户如果没写协议头，保存时自动补 `https://`。
- 段 2 `Account`：
  - `Username`，`Password`（SecureField，右侧眼睛按钮切换明文）。
- 段 3 `Options`：
  - `Start in folder` TextField（默认 `/`，相对于 URL 的路径）
  - `Allow self-signed certificates` Toggle（默认关）
  - `Parallel connections per download` Stepper 1…8（默认 4）
- 段 4：按钮 `Test Connection`（整行按钮，`.pinkInk`）。点击后按钮行变为 `ProgressView` + `Connecting…`，结果显示在按钮下方的一行：成功 `checkmark.circle.fill` success 色 + `Connected. 12 items in root.`；失败 `xmark.octagon.fill` danger 色 + 错误文案。
- Save：不强制测试成功也能保存（离线也允许添加）。保存时密码写入 Keychain，其余写 servers.json。

## 4. 文件浏览 BrowserView
### 4.1 导航栏
- 标题 = 当前文件夹名；根目录时 = 位置名（`My iPhone` / 服务器名）。显示模式 `.inline`（文件夹层级深，大标题浪费空间）。
- **标题菜单**（点按标题弹出，`.toolbarTitleMenu`）：列出从根到当前的每一级祖先（倒序，最近的在上），每项 `Label(name, systemImage: "folder")`，点击直接跳回该级（截断 `filesPath`）。最后一项是位置根（`My iPhone` 或服务器名）。这是“返回任意上一级”的快捷方式。
- 系统返回按钮：返回上一级（系统自带，长按返回按钮也会显示历史栈，系统自带）。
- `.searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search in \(folderName)")`。只过滤当前文件夹（名称包含，大小写与变音不敏感 `localizedStandardContains`）。本地位置额外提供作用域 `.searchScopes($scope) { Text("This Folder").tag(.folder); Text("Everywhere").tag(.all) }`，Everywhere 时递归搜索 Documents（`FileManager.enumerator`，后台，最多 500 条结果，结果行副标题显示所在文件夹路径）。WebDAV 只有 This Folder。

### 4.2 右上工具栏（从左到右）
1. `+` 按钮（`Menu`，图标 `plus`）：
   - `New Folder`（folder.badge.plus）
   - `New Text File`（doc.badge.plus）
   - Divider
   - `Import from Files`（folder）
   - `Import from Photos`（photo.on.rectangle）
   - （仅 WebDAV 位置）`Upload from My iPhone`（iphone.and.arrow.forward）→ DestinationPicker 反向：打开一个本地文件选择器（复用 BrowserView 的选择模式，标题 `Choose Files`，底部按钮 `Upload`）
2. `ellipsis.circle` 按钮（`Menu`）：
   - `Select`（checkmark.circle）→ 进入选择模式
   - Divider
   - 视图切换：`Picker("View", selection: $settings.viewMode) { Label("List", systemImage: "list.bullet").tag(.list); Label("Icons", systemImage: "square.grid.2x2").tag(.grid) }`（在 Menu 中作为 inline picker，显示勾选）
   - 排序：`Picker("Sort By", ...)`：`Name`、`Date`、`Size`、`Kind`；再次选择当前项切换升/降序，当前项右侧显示 `chevron.up` / `chevron.down`（用 `Label(title, systemImage: isAscending ? "chevron.up" : "chevron.down")` 只给当前项）。使用 `Menu("Sort By") { ... }` 子菜单。
   - `Folders on Top` Toggle（默认开）
   - `Show Hidden Files` Toggle（默认关）
   - `Show Extensions` Toggle（默认开）
   - Divider
   - `Get Info`（info.circle，当前文件夹的信息）
   - （WebDAV）`Refresh`（arrow.clockwise）
   以上设置是全局的（AppSettings），不是每个文件夹单独。

两个按钮用 `ToolbarItemGroup(placement: .topBarTrailing)`，系统会把它们合并为一组玻璃胶囊。

### 4.3 列表模式（默认）
`List(selection: $model.selection)`（`selection: Set<FileItem.ID>`），`.listStyle(.plain)`，背景 canvas，行背景 `Color.canvas`（plain 风格下每行无卡片，接近 Files App）。分隔线从文字处开始（系统默认 inset）。

FileRow 布局：
```
[40×40 图标/缩略图]  12  Report final.pdf                    (文件夹显示 chevron.right，文件不显示)
                         2.4 MB · Oct 3, 2026
```
- 第一行：文件名。`Show Extensions` 关闭时文件名去掉扩展名（文件夹始终显示全名）。
- 第二行：文件 = `大小 · 修改日期`；文件夹 = `N items · 修改日期`（本地：异步数子项数量，算出前显示仅日期；WebDAV：不数，只显示日期）。日期：今天显示时间 `3:42 PM`，昨天 `Yesterday`，今年 `Oct 3`，往年 `Oct 3, 2024`。
- 正在下载/上传中的文件：第二行替换为一条细进度条（高 3，圆角，轨道 pinkSoft，进度 pink）+ 百分比。
- 已缓存到本地的远程文件：名称后加一个 10pt 的 `arrow.down.circle.fill` 图标（inkTertiary），表示“离线可用”。
- 当前正在播放的音频文件：名称左边的图标替换为跳动的 `waveform` 符号效果（`.symbolEffect(.variableColor.iterative, isActive: isPlaying)`），色 pinkInk。
- 行高 ≥ 56；`.contentShape(Rectangle())` 让整行可点。

### 4.4 网格模式
`ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 16)], spacing: 20) }`，左右边距 20。
单元：上方 96×96 图标区（文件夹用 64pt `folder.fill` pinkInk；文件用缩略图或 FileKind 图标居中于 surfaceSunken 圆角 14 方块），下方两行文件名（居中，`.lineLimit(2)`，`.truncationMode(.middle)`），再下一行灰色大小或日期。
选择模式下单元右下角显示勾选圆圈。

### 4.5 点击行为（正常模式）
| 目标 | 单击 |
|---|---|
| 文件夹 | push 下一级 BrowserRoute（系统 push 动画） |
| 音频文件 | 用当前文件夹内所有音频（按当前排序）作为队列，从该文件开始播放；**不跳转页面**，迷你播放器出现；同时 toast 无。若用户在设置中把 `Tap audio opens player` 打开（默认关），则同时打开全屏音乐播放器。 |
| 视频文件 | 打开全屏视频播放器（`.fullScreenCover`），队列 = 当前文件夹内所有视频（用于“下一个”） |
| 其他文件 | push `PreviewRoute`（zoom 转场，源为行图标） |

### 4.6 长按菜单（FileContextMenu，列表与网格共用）
用 `.contextMenu { ... } preview: { ... }`。preview：文件夹不提供自定义预览（用系统行快照）；图片显示图片缩略图（最大 300×300）。

单个文件菜单（按此顺序，用 `Section` 分组）：
- Section 1：
  - `Open`（文件夹/预览）或音频 `Play`（play）、视频 `Play`（play.rectangle）
  - 音频额外：`Play Next`（text.line.first.and.arrowtriangle.forward）、`Add to Queue`（text.append）、`Add to Playlist…`（music.note.list）
  - 视频额外：`Add to Playlist…`
  - 文本类/HTML/Markdown 额外：`Edit`（pencil）→ 用文本编辑器打开
- Section 2：
  - `Copy`（doc.on.doc）→ 放入剪贴板（copy 模式）
  - `Cut`（scissors）→ 放入剪贴板（cut 模式）
  - `Duplicate`（plus.square.on.square）→ 同目录生成 `name 2.ext`
  - `Move…`（folder）→ DestinationPicker，确认后 move
  - `Rename`（pencil.line）
- Section 3：
  - `Share`（square.and.arrow.up）
  - 本地文件：`Compress`（archivebox）；zip 文件：`Uncompress`（archivebox.fill）
  - 远程文件：`Download to My iPhone`（arrow.down.circle）→ DestinationPicker（仅本地）
  - 远程文件：`Make Available Offline` / `Remove Download`（切换是否保留在 RemoteCache 中，见 05）
  - `Get Info`（info.circle）
- Section 4：
  - `Delete`（trash，role: .destructive）→ 二次确认

文件夹菜单：`Open`、`Copy`、`Cut`、`Duplicate`、`Move…`、`Rename`、`Compress`（本地）、`Download to My iPhone`（远程，整个文件夹递归）、`Play All`（始终显示；点击时列出该文件夹第一层的音频文件作为队列播放，若没有音频则 toast `No audio in this folder`）、`Get Info`、`Delete`。

### 4.7 左滑 / 右滑
- 左滑（trailing，`allowsFullSwipe: false`）：两个按钮，从右到左为 `Delete`（`role: .destructive`，点击后二次确认）和 `More`（ellipsis，`.tint(.inkSecondary)`）。`More` 点击后弹出 `.confirmationDialog`，只包含：`Rename`、`Move…`、`Share`、`Get Info`、`Cancel`。
- 右滑（leading）：音频文件 `Play Next`（pink 底，onPink 图标）；其他文件不提供右滑。
- 网格模式没有滑动操作。

### 4.8 选择模式
进入方式只有两种：右上 `…` → `Select`；或在列表模式下双指在行上拖动（List 自带的多选手势，只要 `List(selection:)` 绑定了就会自动进入编辑模式）。不要再加其他入口。

实现：`@State private var editMode: EditMode = .inactive`，`.environment(\.editMode, $editMode)`；进入选择模式时 `withAnimation(.smooth) { editMode = .active }`。

选择模式时：
- 导航栏：左上 `Select All` / `Deselect All`（根据是否全选切换文字），右上 `Button("Done", role: .confirm)`（普通 toolbar 按钮，系统自动做成玻璃）。隐藏系统返回按钮（`.navigationBarBackButtonHidden(editMode.isEditing)`）。标题变为 `N Selected`（0 个时为 `Select Items`）。
- 隐藏搜索框（`.searchable` 仍在，但选择模式下设置 `isPresented = false`），隐藏 `+` 和 `…` 按钮。
- Tab 栏隐藏：`.toolbar(.hidden, for: .tabBar)`，迷你播放器同时隐藏（accessory 随 tab bar）。
- 底部操作条：使用 `.toolbar { ToolbarItemGroup(placement: .bottomBar) { ... } }`，系统会生成 Liquid Glass 底栏。每个按钮都是 `Button { } label: { Label("Share", systemImage: "square.and.arrow.up") }`（bottomBar 中系统只显示图标，文字用于无障碍）。顺序：
  1. `Share`（square.and.arrow.up）
  2. `ToolbarSpacer(.flexible)`
  3. `Copy`（doc.on.doc）
  4. `Move`（folder）→ DestinationPicker
  5. `ToolbarSpacer(.flexible)`
  6. `More`（ellipsis.circle，Menu）：`Cut`、`Duplicate`、`Compress`（本地）、`Download to My iPhone`（远程）、`Add to Queue`（选中项全是音频时）、`Add to Playlist…`（选中项全是音视频时）
  7. `ToolbarSpacer(.flexible)`
  8. `Delete`（trash，tint danger）
  所有按钮在 0 选中时 `.disabled(true)`。
- 执行任意操作后自动退出选择模式（Delete 在确认删除之后退出；取消确认不退出）。
- 点击行 = 切换选中，不打开文件。长按菜单在选择模式下禁用。
- 网格模式下也支持选择：单元点击切换选中，右下角勾选圆圈（`circle` / `checkmark.circle.fill` pink 填充 onPink 勾，`.contentTransition(.symbolEffect(.replace))`）。网格模式不用 List selection，自己维护 `Set<ID>`，与列表模式共用 `model.selection`。

### 4.9 复制 / 剪切 / 粘贴
- `Clipboard`：
  ```swift
  @MainActor @Observable final class Clipboard {
      enum Mode { case copy, cut }
      private(set) var items: [FileItem] = []
      private(set) var mode: Mode = .copy
      func set(_ items: [FileItem], mode: Mode)
      func clear()
      var isEmpty: Bool
  }
  ```
- 放入剪贴板时 toast：`Copied 3 items to clipboard` / `Cut 3 items`，`symbol: doc.on.clipboard`。cut 模式下，这些文件在列表中以 50% 不透明度显示（直到粘贴或清除）。
- **PasteBar**：剪贴板非空，且当前浏览的文件夹不是剪贴板中任何文件夹本身/子孙时，在 BrowserView 底部（Tab 栏上方，用 `.safeAreaInset(edge: .bottom)`）浮出一个玻璃胶囊条：
  ```
  ( doc.on.clipboard  3 items · Paste here )   ( xmark )
  ```
  - 左胶囊（主按钮，`.glassEffect(.regular.tint(.pink).interactive(), in: .capsule)`，文字 onPink）：点击执行 `operations.transfer(clipboard.items, to: 当前位置, destDir: 当前路径, move: mode == .cut)`，然后 cut 模式清空剪贴板，copy 模式保留（可多次粘贴）。
  - 右圆形按钮（`.glassEffect(.regular.interactive(), in: .circle)`，xmark）：清空剪贴板。
  - 两者包在 `GlassEffectContainer(spacing: 8)` 内，用 `glassEffectID` 让它们出现/消失时液态形变；出现动画 `.smooth`。
  - 选择模式下不显示 PasteBar。
- `+` 菜单中，剪贴板非空时在最上方增加 `Paste`（doc.on.clipboard）。
- 粘贴到同一目录（copy 模式）= 自动 Keep Both（生成 `name 2`），不弹冲突框。

### 4.10 重命名 RenameSheet
**不要用 alert 输入**，用一个小 sheet：
- `.sheet`，`.presentationDetents([.height(220)])`，`NavigationStack`，标题 `Rename`（inline），左 `Cancel`，右 `Save`（名称无效或未改动时禁用）。
- 内容：一个大号 TextField（surfaceSunken 背景，圆角 14，内边距 14，`.cofferBody`），下方一行 caption 说明。
- 打开时自动聚焦，**并且只选中主文件名部分，不选中扩展名**（文件夹全选）。实现：使用 `TextField(text: $name, selection: $selection)`（iOS 18+ `TextSelection`），在 `onAppear` 后设置 `selection = TextSelection(range: name.startIndex..<baseEnd)`，`@FocusState` 设为 true。
- 扩展名始终显示在输入框中（用户可以改）。如果用户修改了扩展名，Save 时弹 `.confirmationDialog`：`Change extension from ".txt" to ".md"?`，按钮 `Use ".md"`、`Keep ".txt"`、`Cancel`。
- 实时校验：名称为空 → caption 显示 `Name can't be empty`（danger 色）；含 `/` → `Names can't contain "/"`；与同目录其他项重名（不区分大小写，排除自身）→ `An item with this name already exists`。校验通过时 caption 显示原名 `Was: Report.pdf`（inkSecondary）。
- 回车键 = Save。

### 4.11 新建 NewItemSheet
- `New Folder`：与 Rename 相同的 sheet 外观，标题 `New Folder`，默认名 `New Folder`（已存在则 `New Folder 2`），全选，右上 `Create`。创建成功后列表中插入新行（动画），并把该行滚动到可见位置，轻微高亮 1 秒（行背景 pinkSoft → 恢复）。
- `New Text File`：默认名 `Untitled.txt`，只选中 `Untitled`；创建空文件后**直接**用文本编辑器打开（全屏 sheet，见 08）。

### 4.12 删除
- 确认：`.confirmationDialog`，标题 `Delete "Report.pdf"?` 或 `Delete 3 items?`，message `This can't be undone.`，按钮 `Delete`（destructive）、`Cancel`。
- 远程删除时 message 改为 `This will delete it from "Home NAS". This can't be undone.`。
- 删除成功：行以动画移除，触感 `.warning`。不弹 toast。部分失败：toast `Couldn't delete 1 item` 并带错误原因。

### 4.13 Get Info（InfoSheet）
`.sheet` `.presentationDetents([.medium, .large])`，顶部大图标/缩略图（96pt），文件名（cofferTitle，可多行），下面 `Form` 风格的键值列表：
- Kind（例如 `MP4 Video`、`Folder`；用 `UTType(filenameExtension:)?.localizedDescription`，无则 `"\(EXT) File"`）
- Size（`2.4 MB (2,457,600 bytes)`；文件夹在本地递归计算，显示 `Calculating…` 后更新；远程文件夹显示 `—`）
- Where（`My iPhone › Music › Albums`）
- Created / Modified（完整日期时间）
- 媒体文件额外：Duration、Dimensions（视频/图片）、Codec（能读到时）、Bitrate
- 图片额外：Dimensions、Camera（EXIF 有则显示）
- WebDAV 额外：`URL`（可长按复制）、`ETag`
底部按钮行：`Copy Path`（复制路径到系统剪贴板，toast `Copied`）。

### 4.14 DestinationPicker
用于 Move… / Copy to… / Download to My iPhone / Upload / 导入目标。
- `.sheet`，`.presentationDetents([.large])`，内部自己的 `NavigationStack`。
- 根页面：位置列表（My iPhone + 各 WebDAV；`allowedLocations` 参数限制可选位置，例如 Download to My iPhone 只允许 local）。如果只有一个允许的位置，直接从该位置根开始。
- 文件夹页面：只列出文件夹（文件以 40% 不透明度显示且不可点，帮助用户认路），点击文件夹进入下一级。
- 导航栏：标题 = 当前文件夹名；左上 `Cancel`；右上 `New Folder` 图标按钮（folder.badge.plus）。
- 底部：`.safeAreaInset(edge: .bottom)` 一个大按钮 `Move Here` / `Copy Here` / `Save Here` / `Upload Here`（文案由调用方传入），`.buttonStyle(.glassProminent)` tint pink，`.controlSize(.large)`，水平撑满（左右 20）。当目标 == 源文件夹（move 时）或目标是被移动文件夹自身/子孙时禁用，并在按钮上方显示 caption 原因。
- 打开时默认定位到“源文件所在文件夹”（直接把路径栈设置好）。

### 4.15 拖放（iPad 与 iPhone 都支持）
- 本地文件行 `.onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }`，可以把文件拖到其他 App。远程文件不支持拖出。
- 文件夹行与当前文件夹空白处 `.dropDestination(for: URL.self) { urls, _ in importFiles(urls, to: folder) }`：从其他 App 拖入文件。
- App 内拖到文件夹行上 = 移动（本地同位置）。拖动悬停在文件夹上时行背景 pinkSoft。
（拖放属于加分项，放在最后阶段做。）

### 4.16 下拉刷新与加载
- `.refreshable` 在所有位置可用（本地重新 list，远程强制 PROPFIND）。
- 远程首次进入目录：若有缓存（dir-cache）立即显示缓存，同时后台刷新，`navigationSubtitle("Updating…")`；无缓存时中间 `ProgressView()`。
- 加载失败且无缓存：`ContentUnavailableView("Couldn't load this folder", systemImage: "wifi.exclamationmark", description: Text(error))` + 按钮 `Try Again`。
- 有缓存但刷新失败：保留缓存列表，`navigationSubtitle("Offline · Showing saved list")`。

### 4.17 空文件夹
`ContentUnavailableView { Label("This folder is empty", systemImage: "folder") } description: { Text("Tap + to add files or create a folder.") } actions: { Menu("Add") { 与 + 菜单相同 } .buttonStyle(.glass) }`

## 5. BrowserModel
```swift
@MainActor @Observable final class BrowserModel {
    let location: LocationID
    let path: String
    private(set) var items: [FileItem] = []       // 原始（未过滤）
    var query = ""
    var selection = Set<FileItem.ID>()
    private(set) var isLoading = false
    private(set) var isStale = false              // 显示的是缓存
    private(set) var error: Error?
    var visibleItems: [FileItem]                   // 计算属性：过滤隐藏文件 → 搜索 → 排序（folders on top）
    func load() async                              // 首次
    func reload(force: Bool = false) async
}
```
排序规则：
- Name：`localizedStandardCompare`（自然排序，“file2” 在 “file10” 前）。
- Date：modified 降序为默认（首次切换到 Date 时默认降序；Name 默认升序；Size 默认降序；Kind 按 FileKind.rawValue 再按名称）。
- Folders on Top：文件夹始终排在文件前，文件夹之间同样按当前排序。
- 排序变化时用 `withAnimation(.smooth)` 让行重新排列。
