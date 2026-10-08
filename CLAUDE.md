# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Coffer is an iOS 26.1+ file manager (local sandbox + WebDAV) with previews, a music/video player, media libraries and a text editor. SwiftUI, Swift 5 language mode, strict concurrency `minimal`. The spec lives in `docs/` (written in Chinese); `PROMPT.md` holds the original task brief and the non-negotiable rules. `docs/PROGRESS.md` is the change log: append a dated, versioned entry describing each change, deviations from the docs, and what was/wasn't verified.

## Build

- `./scripts/build.sh` is the only build check. It regenerates the Xcode project with xcodegen, then builds for `generic/platform=iOS` with signing disabled, using Xcode beta at `/Applications/Xcode-beta.app` (override via `DEVELOPER_DIR`). Success means the last line is `BUILD OK`. Full log: `build/last-build.log`.
- `./scripts/fetch-vlckit.sh` downloads MobileVLCKit into `Vendor/` (~250 MB, resumable) if missing.
- No simulator runtime and no test target exist. Correctness is checked by compiling and careful reading; ad-hoc logic checks have been done as macOS harnesses compiling production source files. Don't try to install simulators or run UI tests.
- Not a git repository.

## Project generation

- `project.yml` (XcodeGen) is the source of truth. Never hand-edit `Coffer.xcodeproj`; it is regenerated each build. New `.swift` files under `Coffer/Sources` are picked up automatically.
- Versions: `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml` (PROGRESS entries reference them, e.g. `1.1 (6)`).
- Dependencies: ZIPFoundation (SPM, pinned 0.9.20, `import ZIPFoundation`) and `Vendor/MobileVLCKit.xcframework`, exposed via `Coffer/Sources/Support/Coffer-Bridging-Header.h`. Never write `import MobileVLCKit`. Don't add dependencies or change bundle ID, deployment target or Swift mode.
- `Coffer/Resources/Web/` holds bundled JS (marked, DOMPurify, highlight.js, KaTeX as a folder reference) used by WKWebView previews. Don't regenerate `Assets.xcassets` or `Info.plist`.

## Architecture

`docs/02-architecture.md` defines the folder layout and core type signatures; follow it (one primary type per file, keep specified names). Big picture:

- `App/`: `CofferApp` (@main, `onOpenURL`, appearance), `AppServices` owns all singleton services, `RootView` is the `TabView` (Files / Tools) with mini-player `tabViewBottomAccessory`, toasts and conflict dialog. `Navigator` handles cross-tab navigation.
- `FileSystem/`: `FileProvider` protocol abstracts locations; `LocalFileProvider` and `WebDAV/WebDAVFileProvider` implement it, resolved by `FileProviderRegistry` from a `LocationID`. `FileOperations` does copy/move/delete/paste and conflicts; cross-location ops go through `Transfers/TransferManager` (queue, retry, persistence, `SegmentedDownloader`, `Uploader` with temp name + MOVE).
- `WebDAV/`: `WebDAVClient` (HTTP + auth + certs), `PropfindParser`, `RemoteCache` (local copies for preview/edit). Passwords in `Storage/Keychain`.
- `Browser/`: Home, folder browser (`BrowserView` + per-folder `BrowserModel`), context menus, sheets.
- `Preview/`: `PreviewRouter` picks a view by `Model/FileKind`; remote files are downloaded to cache first.
- `Media/`: `PlayerBackend` protocol with `AVPlayerBackend` and `VLCBackend`; `MediaSourceResolver` maps `MediaRef` to URL + headers/options; `AudioPlayer` is the global queue controller; `NowPlayingCenter` for lock screen.
- `Tools/`: music/video/picture libraries (`MediaLibraryIndex`), playlists, text editor. `Settings/`, `Storage/` (`AppSettings` @Observable + UserDefaults, `JSONStore` in Application Support/Coffer/).

## Hard rules (from PROMPT.md, check before finishing)

- No gradients of any kind; `grep -rn "Gradient" Coffer/Sources` must be empty. No emoji anywhere.
- English only in code and UI; copy quoted UI text, SF Symbols, ordering from the docs exactly. When unspecified, mimic Apple's Files (browsing) or Music (audio) app.
- Colors only from `Design/Theme.swift` tokens (`canvas`, `surface`, `surfaceSunken`, `ink*`, `hairline`, `pink`, `pinkInk`, `pinkSoft`, `onPink`, `danger`, `success`); `Color.clear` allowed, black/white only in the video player. Every screen/sheet background is `Color.canvas`. Pink is a fill; pink text/icons use `pinkInk`; content on pink uses `onPink`.
- Native iOS 26 components and Liquid Glass only; never fake glass with materials or put backgrounds on nav/tab/tool bars. Titles use the serif (New York) design.
- Animations `.smooth` / `.snappy` (linear only for progress bars). Never block the main thread with IO.
- UX: row actions only in context menu / swipe actions; no alerts except PDF "Go to Page…"; text input in small sheets; system back navigation only (`.toolbarTitleMenu`, no breadcrumbs); destructive actions confirm via `confirmationDialog` with `role: .destructive`; keep old content while reloading; 44pt hit targets and `accessibilityLabel` on icon-only buttons.
- No `TODO`/`FIXME`, stubs, placeholder views or commented-out code. If an API differs in the SDK, check the `.swiftinterface` files in the Xcode-beta iPhoneOS SDK, use the closest equivalent, and note it in `docs/PROGRESS.md`.
- When docs conflict, the more specific doc wins; note it in PROGRESS.
