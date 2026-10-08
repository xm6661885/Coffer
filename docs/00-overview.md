# 00 · 总览（Coffer）

## 产品一句话
Coffer 是一个 iOS 26 文件管理器：本机沙盒空间 + WebDAV 挂载 + 几乎全格式预览 + 内置文本编辑器 / 音乐播放器 / 视频播放器。自用，不上架。

- App 名：**Coffer**（显示名 `Coffer`，Bundle ID `app.coffer.Coffer`）
- 平台：iPhone 为主，iPad 能跑即可（TARGETED_DEVICE_FAMILY 1,2）
- 最低系统：**iOS 26.1**（Liquid Glass 原生 API；`tabViewBottomAccessory(isEnabled:)` 需要 26.1）
- UI 语言：**全部英文**。代码里所有用户可见字符串都用英文，直接写字面量，不做本地化文件。
- 外观：自动跟随系统深浅色，设置里可强制 Light / Dark。

## 硬性规则（违反任何一条都算没完成）
1. 禁止渐变色：不允许 `LinearGradient` / `RadialGradient` / `AngularGradient` / `MeshGradient` / `.gradient` 修饰（例如 `Color.pink.gradient`）。
2. 禁止 emoji：任何字符串、注释、图标里都不能出现 emoji。图标一律 SF Symbols 或资产目录里的 `CofferGlyph`。
3. 控件尽量用 iOS 26 原生：`NavigationStack`、`TabView`+`Tab`、`.toolbar`、`.searchable`、`List`、`Menu`、`.contextMenu`、`.swipeActions`、`.sheet`、`.confirmationDialog`、`.glassEffect`、`.buttonStyle(.glass / .glassProminent)`、`GlassEffectContainer`。不要自己画假的“玻璃”（不要用 `.ultraThinMaterial` 模拟导航栏/按钮）。
4. 不要给系统导航栏、Tab 栏、工具栏设置背景色或 `UINavigationBarAppearance().configureWithOpaqueBackground()`，否则会破坏系统玻璃。
5. 颜色只能用 `docs/01-design-system.md` 中定义的 token（`Color.canvas` 等），不能在视图里写死 `Color(red:...)` 或 `.blue` / `.red` 等系统色（`Color.clear`、`Color.black`（仅视频播放器背景）、`Color.white`（仅视频播放器上的文字/图标）除外）。
6. 不用第三方 UI 库。允许的第三方依赖只有：MobileVLCKit（已由脚本下载）、ZIPFoundation（SPM，已在 project.yml 声明）、`Coffer/Resources/Web/` 里已放好的 marked / DOMPurify / highlight.js。不要再新增依赖。
7. 不要改 `project.yml` 里的依赖、Bundle ID、部署版本；只有在新增 Info.plist key 或资源时才可以动，且必须说明原因。
8. 每完成一个阶段必须运行 `./scripts/build.sh` 直到最后一行输出 `BUILD OK`。

## 技术选型（已定，不要更换）
| 领域 | 方案 |
|---|---|
| UI | SwiftUI（iOS 26），必要处用 `UIViewRepresentable` 包 UIKit（UITextView、WKWebView、PDFView、UIScrollView、QLPreviewController、AVPlayerLayer、VLC 视频视图） |
| 状态 | Observation 框架：`@Observable` + `@MainActor final class`；视图里 `@State private var model = ...`、`@Environment(Type.self)` 注入单例服务 |
| 语言模式 | Swift 5 语言模式（project.yml 已设 `SWIFT_VERSION 5.0`，`SWIFT_STRICT_CONCURRENCY minimal`）。不要改成 Swift 6。 |
| 本地文件 | `FileManager`，根目录 = App 的 `Documents/` |
| WebDAV | 自己实现，基于 `URLSession` + `XMLParser`，不使用第三方库 |
| 传输 | 自己实现的 `TransferManager`：分段多连接下载、断点续传、指数退避重试、上传先传临时名再 MOVE |
| 音视频 | `AVPlayer`（系统支持的格式，支持画中画）+ `MobileVLCKit` 的 `VLCMediaPlayer`（其余格式：mkv/avi/flv/wmv/rmvb/ogg/opus/ape/wma 等） |
| Markdown/HTML/代码高亮 | `WKWebView` + 本地 `marked.umd.js` + `purify.min.js` + `highlight.min.js` |
| PDF | PDFKit |
| Office/RTF/iWork 等 | QuickLook（`QLPreviewController`） |
| 压缩包 | ZIPFoundation（仅 zip：浏览 + 解压 + 压缩） |
| 缩略图 | QuickLookThumbnailing（`QLThumbnailGenerator`） |
| 持久化 | `UserDefaults`（设置）、JSON 文件放 `Application Support/Coffer/`（服务器列表、播放列表、传输队列、播放进度、最近文件）、Keychain（WebDAV 密码） |

## 已经准备好的东西（不要删除/覆盖）
```
Coffer/                         ← 仓库根（桌面上的 Coffer 文件夹）
├── PROMPT.md                   ← 给 Codex 的总指令
├── project.yml                 ← XcodeGen 工程定义（不要手改 .xcodeproj）
├── scripts/
│   ├── build.sh                ← 生成工程并编译（判定标准：输出 BUILD OK）
│   └── fetch-vlckit.sh         ← 下载 MobileVLCKit.xcframework 到 Vendor/（约 250MB，可断点续传）
├── Vendor/                     ← fetch-vlckit.sh 的输出（被 .gitignore 忽略）
├── docs/                       ← 本文档集 + icon/ 源文件
└── Coffer/
    ├── Resources/
    │   ├── Info.plist          ← 已配置文件共享/打开方式/后台音频/ATS，见 03 文档
    │   ├── Assets.xcassets     ← AppIcon（浅/深/着色）、颜色 token、CofferGlyph
    │   └── Web/                ← marked.umd.js / purify.min.js / highlight.min.js
    └── Sources/
        ├── CofferApp.swift     ← 占位入口，需替换
        └── Support/Coffer-Bridging-Header.h  ← 已 #import MobileVLCKit
```

## 文档索引（按顺序阅读）
1. `01-design-system.md` 视觉规范、颜色、字体、玻璃、动画、图标
2. `02-architecture.md` 源码目录、每个文件的职责、核心类型签名
3. `03-local-storage.md` 沙盒、Files App 可见、分享菜单导入、本地文件操作细节
4. `04-files-ui.md` 首页 / 文件浏览器 / 选择模式 / 复制粘贴 / 重命名 等全部交互
5. `05-webdav-transfers.md` WebDAV 协议实现、缓存、传输引擎、传输面板
6. `06-preview.md` 各格式预览
7. `07-media-player.md` 音频引擎、迷你播放器、全屏音乐播放器、视频播放器（手势/画中画/旋转/后台）
8. `08-tools-settings.md` 工具 Tab：文本编辑器、音乐库、视频库、播放列表、设置
9. `09-phases.md` 分阶段实施清单与每阶段验收点
