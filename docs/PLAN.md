# CarPlayTV — Product & Technical Plan

Status: draft v1 (pre-code). UI design is deferred; this covers capabilities, architecture, risks and phasing.

> Note on reference app: "CarTV"-style apps play video and mirror the phone on the CarPlay screen.
> The feature list below is the typical capability set for that category. Before Phase 1, confirm it
> against the exact app you want to match (screenshots or a feature list), and adjust scope.

---

## 1. How video gets onto a CarPlay screen

See `docs/CARTV_ANALYSIS.md` for the research. Summary: **CarTV is an App Store app** and has three
routes onto the car screen: **Direct** (own sources), **Receive** (UPnP/DLNA renderer) and **Mirror**
(ReplayKit). Video is "drawn in the CarPlay window". That points to a **CarPlay navigation entitlement**
whose `CPWindow` is filled with a video layer instead of a map (not yet confirmed — check the IPA's entitlements).

| Path | How it works | Distribution | Verdict |
|---|---|---|---|
| **A. Navigation-entitlement canvas (CarTV's approach)** | `com.apple.developer.carplay-maps` gives a `CPWindow`; put `AVPlayerLayer` / `AVSampleBufferDisplayLayer` in it, with `CPMapTemplate` buttons on top. | App Store (CarTV-type apps are live), but Apple could reject or remove the app for misusing the entitlement. Works in the Xcode CarPlay Simulator. | **Primary**, for CarTV parity on all CarPlay cars, iOS 18+. |
| **B. Official CarPlay video app (iOS 27+)** | `com.apple.developer.carplay-video` + AirPlay video; parked only; supported vehicles; `CPPlaybackConfiguration`, MiniPlayer. | App Store, sanctioned by Apple. | **Add alongside A**: low risk, but only on supported cars. |
| **C. Audio-only CarPlay app** | `com.apple.developer.carplay-audio`; audio + now-playing on the car. | App Store. | Always-on fallback, used while driving. |
| D. Private APIs / TrollStore | Private CarKit APIs. | Sideload only. | **Dropped** — not needed. |

**Recommendation:** a single App Store build with a pluggable **`CarDisplayBackend`**:
`NavCanvasBackend` (A), `CarPlayVideoBackend` (B, iOS 27+), `AudioBackend` (C). Phase 0 confirms CarTV's
entitlement and gets video rendering in the CarPlay Simulator. Apply for the CarPlay entitlements early,
because Apple's approval takes weeks.

---

## 2. Feature scope (mimicking CarTV-class apps)

### 2.1 Core (MVP)
1. **Web video / browser mode** — built-in `WKWebView` browser rendered on the car screen; bookmarks
   for YouTube, Twitch, etc.; video auto-fullscreen; desktop/mobile UA toggle.
2. **Direct stream playback** — paste/open any URL (HLS `.m3u8`, MP4, MKV via fallback decoder).
3. **IPTV** — import M3U/M3U8 playlists and Xtream Codes logins; EPG (XMLTV); channel groups,
   favourites, search.
4. **Local media** — play files from the Files app / iCloud Drive / Photos library.
5. **Screen mirroring** — mirror the phone screen to the car display (ReplayKit Broadcast Upload
   Extension → frames handed to the main app → rendered on the car canvas).
6. **Phone-as-remote** — the phone shows controls (play/pause, seek, volume, playlist, trackpad
   cursor for the web browser) while video shows on the car.
7. **Safety / driving lock** — video hidden when the car is moving; audio continues (see §4).
8. **Receive (DLNA/UPnP MediaRenderer)** — SSDP + AVTransport/RenderingControl/ConnectionManager so
   Plex, Infuse, VLC, Bilibili etc. can cast to the car. (Google Cast/YouTube is not possible — use Mirror.)
9. **Live Activity** on the Lock Screen while casting/mirroring; free-tier limits + Pro paywall.

### 2.2 Phase-2 features
- Media servers: **Plex, Jellyfin, Emby**, DLNA/UPnP, SMB/WebDAV network shares.
- Subtitles (SRT/VTT/embedded), audio track selection, playback speed, aspect-ratio / zoom / fill.
- Resume positions, watch history, Continue Watching.
- Picture-in-Picture on the phone; background audio.
- Siri / App Shortcuts ("Play channel X"), widget for quick launch.
- Multiple profiles, parental PIN.

### 2.3 Explicit non-goals
- Bypassing DRM (Netflix, Disney+, Prime use FairPlay; they render black when mirrored — we will not
  circumvent this). These services can be offered only via their web players where they permit it.
- Downloading/ripping YouTube streams (violates YouTube ToS) — use the embedded web player only.

---

## 3. Architecture

**Stack:** Swift 6, SwiftUI (phone UI), UIKit (car canvas), AVFoundation, CarPlay framework, Swift
Concurrency, SwiftData (or GRDB) for persistence. Min iOS: 18 (same as CarTV); official CarPlay video
entitlement features gated to iOS 27+. Fallback decoder for non-native containers: **VLCKit** (MobileVLCKit) or
**KSPlayer/FFmpeg** — evaluated in Phase 0.

```
CarPlayTV (app target)
├── App/                  App & scene delegates (phone scene + CarPlay scene)
├── Features/             Phone UI per feature (Browser, IPTV, Library, Mirror, Settings)
├── Packages/ (SPM)
│   ├── CarDisplayKit     CarDisplayBackend protocol + Template / Canvas / AirPlay backends
│   ├── PlaybackKit       Unified player (AVPlayer + fallback decoder), queue, now-playing, remote cmds
│   ├── SourcesKit        Source protocol; WebSource, URLSource, IPTVSource(M3U, Xtream, EPG),
│   │                     LocalSource, later PlexSource/JellyfinSource/DLNASource
│   ├── MirrorKit         ReplayKit extension bridge (App Group + shared memory / IOSurface), renderer
│   ├── SafetyKit         DriveStateMonitor (speed, motion activity, CarPlay parked hints)
│   ├── RemoteControlKit  Phone remote: trackpad, D-pad, gestures → car canvas / web view
│   └── CoreKit           Persistence, settings, logging, networking, keychain
└── BroadcastExtension/   ReplayKit Broadcast Upload Extension (mirroring)
```

Key design rules:
- **Player is display-agnostic**: `PlaybackKit` outputs to an `AVPlayerLayer`/`CALayer`; whichever
  `CarDisplayBackend` is active hosts that layer (car canvas, AirPlay route, or phone).
- **Single source of truth** for playback state (`@Observable` store) shared by phone UI, CarPlay
  templates and `MPNowPlayingInfoCenter`.
- **Each display backend sits behind a feature flag** (plus `#available` checks for iOS 27), so an App Review
  problem with one path doesn't block a release.

### 3.1 Car canvas specifics
- Car screens vary (800×480 → 1920×720 ultra-wide, different scale factors); layout must adapt to
  `CPWindow` / screen bounds and safe areas.
- Input on the car side is limited (touch may or may not reach the canvas; knob/touchpad cars send
  focus events). Primary control is therefore the **phone-as-remote**, with simple on-car overlays.
- Audio routing: use `.playback` audio session; video audio goes to the car via the CarPlay audio
  channel; duck for navigation prompts.

### 3.2 Mirroring pipeline
ReplayKit broadcast extension (≈50 MB memory cap) → receive `CMSampleBuffer`s → downscale/convert
→ pass to main app via App Group (shared `IOSurface` / Mach port or local socket) → render in a
`AVSampleBufferDisplayLayer` on the car canvas. Target: ≤150 ms latency, 30 fps, rotation handling.

---

## 4. Safety & legal (non-negotiable)

- **Video only while parked.** `DriveStateMonitor` combines CoreLocation speed (> ~5 km/h = moving),
  `CMMotionActivityManager` (automotive), and hysteresis to avoid flicker. When moving: hide video,
  show a "Video paused while driving" card, keep audio playing.
- First-run disclaimer + acknowledgement; passenger-mode toggle is **not** offered to bypass the lock
  (liability) — revisit with legal advice.
- Respect content terms: no DRM circumvention, no stream ripping; IPTV is "bring your own playlist",
  app ships with no channels.
- Privacy: location used only on-device for speed; disclose in privacy manifest
  (`PrivacyInfo.xcprivacy`) and App Store privacy labels.

---

## 5. Non-functional requirements
- Start-up to first frame on car < 3 s for direct streams.
- Seamless reconnect when CarPlay disconnects/reconnects (resume position, re-attach layer).
- Thermal/battery: cap decode resolution to car screen size; drop to audio-only when thermal state
  is `.serious`.
- Accessibility (phone UI), localization-ready strings.
- Crash reporting + privacy-respecting analytics (opt-in).

---

## 6. Testing strategy
- Unit tests: M3U/Xtream/EPG parsers, DriveStateMonitor state machine, playback store.
- Xcode **CarPlay Simulator** (I/O → External Displays → CarPlay) for all display backends, with
  multiple screen sizes.
- Real hardware: Apple's CarPlay test head units or an aftermarket head unit (e.g. Pioneer/Alpine/
  Sony) — wired + wireless CarPlay.
- Simulated driving: GPX route playback in Simulator to test the safety lock.

---

## 7. Phased roadmap

| Phase | Goal | Deliverables | Exit criteria |
|---|---|---|---|
| **0. Feasibility spike** (1–2 wk) | De-risk §1 | Check CarTV's entitlements from its IPA; minimal app showing `AVPlayer` in a `CPWindow` on the CarPlay Simulator; ReplayKit frames → car window prototype; decoder choice (VLCKit vs KSPlayer); file CarPlay entitlement requests with Apple. | Video renders on the simulated car display; entitlements requested. |
| **1. Foundation** (2 wk) | Skeleton | Xcode project, SPM packages, both build flavours, CI (GitHub Actions: build + tests), `CarDisplayBackend` + TemplateBackend, PlaybackKit basics, persistence. | App launches on phone + CarPlay sim; audio now-playing works. |
| **2. Core playback** (3 wk) | MVP sources | URL streams, local files, IPTV (M3U + Xtream + EPG), favourites/history, phone-as-remote, CanvasBackend video, DriveStateMonitor. | Watch an IPTV channel on car while parked; auto-locks when driving. |
| **3. Browser & mirroring** (3 wk) | CarTV parity | Car-rendered web browser with trackpad remote; ReplayKit mirroring pipeline. | YouTube in browser and full-screen mirroring work on the car screen. |
| **4. UI design & polish** (2–3 wk) | Design pass | Phone + car UI design, onboarding, settings, subtitles/tracks, aspect modes. | Usability test on real head unit. |
| **5. Extensions** (3 wk) | Phase-2 features | Plex/Jellyfin/DLNA, Siri/Shortcuts, widgets, PiP, profiles/PIN. | Feature-complete beta. |
| **6. Release** (1–2 wk) | Ship | TestFlight beta, App Review notes explaining the parked-only behaviour, privacy manifest, localizations. | Public App Store release. |

Rough total: ~15–18 weeks for one iOS developer.

---

## 8. Prerequisites
- Mac with Xcode 26+, a paid Apple Developer account.
- iPhone for testing (iOS 18+, plus one on iOS 27 for the official video entitlement).
- A CarPlay head unit (or a car) for real-hardware testing.
- Note: this repo is being worked on from a Linux cloud environment — Swift/iOS builds and the CarPlay
  Simulator need macOS, so builds will run on a Mac or macOS CI runners (GitHub Actions `macos-*`).

---

## 9. Open questions for you
1. **Review risk:** OK to follow CarTV's navigation-canvas approach (with an App Store rejection risk), or launch
   with only the official iOS 27 video entitlement + audio, and add the canvas later?
2. Which exact features of CarTV are must-haves for v1 (browser, IPTV, mirroring, local files, media
   servers)?
3. Minimum iOS version and target devices?
4. Monetisation (free, one-time purchase, subscription)? Affects StoreKit work.
5. Any branding/name constraints — we must not reuse CarTV's name, icon or assets.
