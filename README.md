# CarPlayTV

Video on the CarPlay display: your own M3U/IPTV playlists, media servers and local files, with
casting and screen mirroring to come. See `docs/PLAN.md` for the plan and `docs/CARTV_ANALYSIS.md`
for how the reference app (CarTV) works.

**For passenger use only. Video is paused on the car display while the car is moving.**

## How it reaches the car screen
Like CarTV, the app uses the CarPlay **navigation** entitlement (`com.apple.developer.carplay-maps`).
That gives a `CPWindow` the app can draw into; we put an `AVPlayerLayer` there instead of a map, and a
`CPMapTemplate` on top supplies the buttons (previous / play-pause / next, Channels, Line).

## Layout
| Path | What |
|---|---|
| `project.yml` | XcodeGen spec (the `.xcodeproj` is generated, not committed) |
| `App/Phone` | SwiftUI iPhone app (placeholder UI until the design phase) |
| `App/CarPlay` | CarPlay scene delegate + video canvas for the car window |
| `App/Shared` | `AppModel` (state shared by both scenes), player layer view |
| `Packages/CarPlayTVKit` | `SourcesKit` (M3U parser, loader), `PlaybackKit` (AVPlayer controller), `SafetyKit` (driving lock) |

## Run it (needs a Mac)
1. `brew install xcodegen`, then `xcodegen generate` in the repo root.
2. Open `CarPlayTV.xcodeproj`, pick your team under Signing & Capabilities, run on an iPhone simulator.
3. In Simulator: **I/O → External Displays → CarPlay**. Open CarPlayTV on the car screen.
4. On the phone, load a playlist or paste a stream URL, e.g. Apple's test stream
   `https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8`.
5. Test the driving lock with **Features → Location → Freeway Drive**.

Package tests: `swift test --package-path Packages/CarPlayTVKit`.

### On a real iPhone + car
The navigation entitlement must be granted to your Apple Developer team by Apple
(request it at developer.apple.com/carplay). Until then, use the CarPlay Simulator.
