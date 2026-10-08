# Task: build "Coffer", an iOS 26 file manager, exactly as specified

You are implementing a complete iOS app in this folder. Every design and interaction decision has already been made and written down in `docs/`. Your job is to implement those documents faithfully, phase by phase, and keep the project compiling. Do not redesign anything.

## Read first (in this order, fully, before writing code)
1. `docs/00-overview.md` — product, hard rules, tech stack, what already exists
2. `docs/01-design-system.md` — colors, fonts, Liquid Glass usage, animation, icons
3. `docs/02-architecture.md` — the exact folder/file layout and core type signatures
4. `docs/03-local-storage.md` — sandbox, Files app visibility, share-sheet import, local file ops
5. `docs/04-files-ui.md` — home screen and file browser interactions (most important for UX)
6. `docs/05-webdav-transfers.md` — WebDAV client and the transfer engine
7. `docs/06-preview.md` — file previews
8. `docs/07-media-player.md` — music player, mini player, video player
9. `docs/08-tools-settings.md` — Tools tab, playlists, libraries, text editor, settings
10. `docs/09-phases.md` — the implementation order and acceptance checks

The documents are written in Chinese. All code, identifiers, comments and every user-visible string must be in English, exactly as quoted in the documents (quoted UI text is in backticks).

## Environment
- macOS with **Xcode 27.2 beta** at `/Applications/Xcode-beta.app` (iOS 27.2 SDK). The build script sets `DEVELOPER_DIR` for you. Deployment target is iOS 26.1.
- `xcodegen` is installed. The Xcode project is generated from `project.yml`. Never edit `Coffer.xcodeproj` by hand; it is regenerated on every build.
- Build check: `./scripts/build.sh`. It must end with the line `BUILD OK`. Signing is disabled for the check; the user will sign and install on a real device themselves.
- MobileVLCKit: `./scripts/fetch-vlckit.sh` downloads it into `Vendor/` (~250 MB, resumable; re-run it if interrupted). It is exposed to Swift through `Coffer/Sources/Support/Coffer-Bridging-Header.h`. Do not write `import MobileVLCKit`.
- ZIPFoundation is declared in `project.yml` as a Swift package (pinned 0.9.20). Use `import ZIPFoundation`.
- `Coffer/Resources/Web/` already contains `marked.umd.js`, `purify.min.js`, `highlight.min.js`.
- `Coffer/Resources/Assets.xcassets` already contains the app icon (light/dark/tinted), all color tokens and the `CofferGlyph` image. `Coffer/Resources/Info.plist` is already configured. Do not modify or regenerate them unless a document explicitly says so.
- There is no simulator runtime installed and you cannot run the app. Correctness is checked by compiling and by careful reading of the spec. Do not try to install simulators or run UI tests.

## How to work
1. Follow `docs/09-phases.md` strictly in order: P0, P1, ... P10. Finish one phase completely before starting the next.
2. At the end of every phase run `./scripts/build.sh`. If it fails, read the errors (the script prints errors from our sources; the full log is `build/last-build.log`), fix them, and rebuild until `BUILD OK`. Also fix all warnings in our own sources that you can fix safely.
3. After each phase, append a line to `docs/PROGRESS.md` (create it in P0), e.g. `- [x] P4 · Previews · BUILD OK`, followed by one or two lines about anything you could not do exactly as specified and why.
4. Create files exactly at the paths listed in `docs/02-architecture.md`. One primary type per file. You may add small private helper types inside a file. If you need a file the docs do not list, put it in the closest matching folder and mention it in `docs/PROGRESS.md`.
5. Use the type and method signatures given in the docs. You may add members, but do not rename or remove the specified ones.
6. When a document gives exact UI text, SF Symbol names, sizes, colors, ordering of menu items, or behavior, copy it exactly. When something is not specified, copy the behavior of Apple's built-in Files app (for file browsing) or Music app (for audio), and use system components with default styling.
7. If an API named in the docs does not exist or has a different signature in this SDK, look it up in the SDK's `.swiftinterface` files (under `/Applications/Xcode-beta.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/<Framework>.framework/Modules/`), use the closest equivalent that achieves the same visible result, and note it in `docs/PROGRESS.md`. Do not drop the feature.
8. Never leave `TODO`, `FIXME`, placeholder views, stub methods, `fatalError` in non-init code, or commented-out code. If something truly cannot be done, implement the nearest working behavior and explain it in `docs/PROGRESS.md`.
9. Do not add any dependency, Swift package, CocoaPod, or script. Do not change the bundle ID, deployment target, or Swift language mode.

## Non-negotiable rules (re-check before finishing every phase)
- No gradients of any kind (`LinearGradient`, `RadialGradient`, `AngularGradient`, `EllipticalGradient`, `MeshGradient`, `.gradient`). Search the code for `Gradient` before each build.
- No emoji anywhere: code, comments, strings, asset names.
- English only in the UI.
- Colors only from the tokens in `Design/Theme.swift` (`Color.canvas`, `.surface`, `.surfaceSunken`, `.ink`, `.inkSecondary`, `.inkTertiary`, `.hairline`, `.pink`, `.pinkInk`, `.pinkSoft`, `.onPink`, `.danger`, `.success`). Exceptions: `Color.clear`; `Color.black` and `Color.white` only inside the video player.
- Use native iOS 26 components and Liquid Glass: `NavigationStack`, `TabView` with `Tab`, `.toolbar`, `ToolbarSpacer`, `.searchable`, `List`, `Form`, `Menu`, `.contextMenu`, `.swipeActions`, `.sheet`, `.fullScreenCover`, `.confirmationDialog`, `.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`, `.tabViewBottomAccessory`, `.tabBarMinimizeBehavior`. Never fake glass with materials, never put a background on navigation bars, tab bars or toolbars, never call `configureWithOpaqueBackground`.
- Every screen background is `Color.canvas` (light: warm paper yellow, dark: warm near-black), including inside sheets.
- Brand pink (`Color.pink`, sRGB 0.967, 0.743, 0.788) is a fill color for primary actions, progress and selection. Pink text and icons use `Color.pinkInk`. Content placed on a pink fill uses `Color.onPink`.
- Titles use the serif design (New York) as specified in `docs/01-design-system.md`.
- Animations use `.smooth` or `.snappy` (never `.easeInOut(duration:)` or `.linear` except for progress bars and the indeterminate bar). Use the zoom navigation transitions, symbol content transitions, numeric text transitions and sensory feedback exactly where the docs say.
- Light/dark mode follows the system automatically; Settings can override it.
- Never block the main thread with file or network IO.

## UX quality bar (the most common ways to get this wrong)
Generated UIs often feel mechanical. Avoid these specific mistakes:
- Do not put rows of action buttons inside list rows. Row actions live only in the long-press context menu and swipe actions, as listed in `docs/04-files-ui.md` section 4.6 and 4.7.
- Do not use alerts for choices or for success messages. Use `confirmationDialog`, `Menu`, or a toast. Text input happens in the small sheets described in the docs (rename, new folder), not in alerts. The only alert allowed is "Go to Page…" in the PDF viewer.
- Do not invent your own back button, breadcrumb bar, or ".." row. Use the system back button, the edge swipe, and the title menu (`.toolbarTitleMenu`).
- Tapping an audio file starts playback immediately without leaving the folder. Tapping a video opens the full-screen player. Tapping anything else opens a preview with a zoom transition.
- Rename preselects only the base name, not the extension.
- Keep old content on screen while reloading. Never show a blank screen during a refresh.
- Every sheet has a clear way out (Cancel or Done). Selection mode always has Done.
- Destructive actions always confirm with a `confirmationDialog` whose destructive button has `role: .destructive`.
- After an operation, update lists with animation (`withAnimation(.smooth)`), not by reloading the whole screen abruptly.
- Make every tappable element at least 44x44 points, and give every icon-only button an `accessibilityLabel`.

## Definition of done
- All phases P0 to P10 complete, each recorded in `docs/PROGRESS.md`.
- `./scripts/build.sh` prints `BUILD OK` on the final code.
- `grep -rn "Gradient" Coffer/Sources` returns nothing. `grep -rnP "[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]" Coffer/Sources` returns nothing.
- `docs/PROGRESS.md` ends with a `## Final notes` section listing every deviation from the docs, every unimplemented item, and known issues, so the user can test on a real device.

Start now with P0. Do not ask questions; every decision you need is in the docs. If two documents seem to conflict, the more specific one wins (e.g. `04-files-ui.md` over `01-design-system.md` for browser details), and you note the conflict in `docs/PROGRESS.md`.
