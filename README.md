# CarPlayTV

Video on the CarPlay display, from sources you already have. A player only: it ships with no content.

**For passenger use only. Video on the car display pauses while the car is moving; audio keeps playing.**

## Features
| Area | What's there |
|---|---|
| **Direct** (your sources) | M3U/M3U8 playlists (link, Files, "Open in"), Xtream Codes (live, movies, series), Jellyfin, Emby, local videos imported from Files/Photos |
| **Receive** | UPnP/DLNA MediaRenderer — Plex, Emby, Infuse, VLC, Bilibili etc. can cast to the car |
| **Mirror** | ReplayKit broadcast extension puts the whole iPhone screen on the car display (any app) |
| Playback | Hardware decoding with automatic VLCKit software fallback (MKV, HEVC, DTS, AVI…), multi-line channels with auto line switching, resume, audio/subtitle tracks, external .srt/.vtt with timing offset, fit/fill |
| Library | Groups, search, favorites, Continue Watching, background channel health checks with latency, hide offline channels |
| CarPlay | Full-screen video in the car window; Browse lists for sources, groups, series; playback buttons; mirroring view |
| System | Lock Screen / car Now Playing + remote commands, Live Activity with Stop while casting/mirroring |
| Pro | StoreKit 2 monthly or lifetime; free tier = 1 source + 15 min casting/mirroring per session |
| Safety | Speed-based driving lock, first-launch passengers-only notice |

## How it reaches the car screen
Like CarTV, the app uses the CarPlay **navigation** entitlement. That gives a `CPWindow` the app draws
into; we put the video (or mirrored screen) there, and a `CPMapTemplate` on top supplies the buttons.
See `docs/CARTV_ANALYSIS.md`. The official iOS 27 CarPlay video mode is planned as an added feature (`docs/PLAN.md`, Phase 5).

## Layout
| Path | What |
|---|---|
| `project.yml` | XcodeGen spec (the `.xcodeproj` is generated, not committed) |
| `App/Phone` | SwiftUI iPhone screens (functional; visual design pass comes later) |
| `App/CarPlay` | CarPlay scene delegate, video canvas, browse templates |
| `App/Shared` | `AppModel` and extensions (receiver, mirror), VLC engine, Pro store, Live Activity |
| `BroadcastExtension` | ReplayKit screen-mirroring extension |
| `Widgets` | Live Activity widget extension |
| `Packages/CarPlayTVKit` | `SourcesKit`, `LibraryKit`, `PlaybackKit`, `SafetyKit`, `ReceiverKit`, `MirrorKit` (+ unit tests) |

## Run it (needs a Mac with Xcode 26+)
1. `brew install xcodegen`, then `xcodegen generate` in the repo root.
2. Open `CarPlayTV.xcodeproj`, pick your team for all three targets, run on an iPhone simulator.
3. In Simulator: **I/O → External Displays → CarPlay**, then open CarPlayTV on the car screen.
4. Add a source, e.g. Apple's test stream as a playlist link:
   `https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8`
5. Test the driving lock with **Features → Location → Freeway Drive**.

Package tests: `swift test --package-path Packages/CarPlayTVKit`. CI (GitHub Actions, macOS) runs the tests and builds the app on every push.

Real devices need Apple-granted entitlements — see `docs/APP_STORE.md`.
