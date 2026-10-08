# Coffer

A quiet, paper-like file manager for iOS 26, built with SwiftUI and Liquid Glass. Browse your local sandbox and WebDAV servers, preview almost anything, play music and video, and edit text, all in one app.

## Features

- **Files**: local sandbox and WebDAV locations behind one `FileProvider` abstraction; copy, move, delete, paste with conflict resolution; context menus and swipe actions in the style of Apple's Files app.
- **WebDAV**: Basic/Digest auth, custom certificates, passwords in Keychain, PROPFIND browsing, local cache for preview and editing.
- **Transfers**: persistent queue with retry, segmented downloads, and safe uploads (temp name + MOVE).
- **Preview**: images, PDF, Markdown (with math and code highlighting), source code, archives (ZIP) and more.
- **Media**: AVPlayer and VLC backends, global audio queue with mini player, lock-screen Now Playing, music/video/picture libraries and playlists.
- **Text editor**: code-friendly editor with a keyboard accessory bar.

## Requirements

- Xcode 26 (beta) with the iOS 26.1 SDK
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- iOS 26.1+ device

## Build

```sh
./scripts/fetch-vlckit.sh   # downloads MobileVLCKit into Vendor/ (~250 MB)
./scripts/build.sh          # generates Coffer.xcodeproj and builds; prints BUILD OK
```

`project.yml` is the source of truth; the Xcode project is generated and not committed. Open `Coffer.xcodeproj` after the first build to run on a device.

## Project layout

```
Coffer/Sources/
  App/         app entry, services, root tab view, navigation
  FileSystem/  FileProvider, local + WebDAV providers, operations, transfers
  WebDAV/      client, PROPFIND parser, remote cache
  Browser/     home and folder browser
  Preview/     preview router and viewers
  Media/       player backends, audio queue, Now Playing
  Tools/       media libraries, playlists, text editor
  Settings/, Storage/, Design/
docs/          design and architecture spec (Chinese), PROGRESS.md change log
```

## Dependencies

- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) 0.9.20 (SPM)
- [MobileVLCKit](https://code.videolan.org/videolan/VLCKit) (fetched by script)
- Bundled web assets: marked, DOMPurify, highlight.js, KaTeX
