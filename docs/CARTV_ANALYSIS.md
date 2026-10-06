# How CarTV puts video on the CarPlay screen — research notes

Researched 2026-10-06. Sources: the developer's own published site text (llms.txt + i18n strings in
github.com/ekucet/cartv-cast), App Store listing snippets, Apple WWDC26 session 212.

## Which app
Two similarly named App Store apps exist, both with the same 3-route design:
- **CarTV – M3U IPTV Player & Cast** (id6800211040, cartv.app) — iOS 18+, Pro $3.99/wk, $45.99/yr, $21.49 lifetime.
- **CarTV Cast** (id6814788876, ekucet.github.io/cartv-cast) — iOS 26.1+, Pro $5.99/mo (3-day trial) or $14.99 lifetime.
  Free tier: 1 source + 15 min casting per session. RevenueCat for purchases. 22 languages.

Both are **on the App Store** — not sideloaded, not jailbreak.

## The three routes onto the car display (developer's own description)

| Route | Mechanism | Network |
|---|---|---|
| **Direct** | User's own sources (M3U/M3U8, Xtream Codes, Jellyfin, Emby, local files from Files/Photos). Decoded on iPhone and *"drawn in the CarPlay window"*. | None needed for local files |
| **Receive** | App is a **UPnP/DLNA MediaRenderer**: SSDP discovery + AVTransport, RenderingControl, ConnectionManager. Advertises "CarTV <iPhone name>". Works with Bilibili, Plex, Emby, Infuse, VLC. **Not** Google Cast (YouTube/TikTok can't see it). | Wi-Fi (local network permission) |
| **Mirror** | **ReplayKit broadcast extension** captures the whole iPhone screen; frames sent to the main app and drawn on the car display over the CarPlay connection. Covers YouTube etc. | None |

Casting/mirroring keep running in the background with a **Lock Screen Live Activity**.

## Playback stack
- AVFoundation hardware decoding first; automatic fallback to **VLCKit** for MKV, HEVC, DTS, AVI. User can pin the software decoder.
- Embedded + external subtitles (incl. MKV tracks, .srt); Pro adds live subtitle offset.
- Resume positions, Continue Watching, favourites, search, mini player.
- Multi-URL channels merged into one entry with a "line switcher".
- Background **channel health checker**: probes every stream, hides dead ones, shows latency (ms), restores them automatically.
- `group-title` → rows, `tvg-logo` → artwork. QR-code scan to add playlist links.
- **Car Mode (Pro)**: landscape phone UI with large controls; answers the car's rotary knob / scroll wheel.
- Privacy: no account, no analytics, credentials in Keychain, everything on-device.
- Positioning: "player only, ships no content", "for passengers only — never watch while driving".

## How the video actually gets onto the CarPlay screen (inference)
The developer says video is "drawn in the CarPlay window". In the public CarPlay framework, the only
category that receives a drawable **`CPWindow`** is a **navigation app** (`com.apple.developer.carplay-maps`):
its `CPMapTemplate` is transparent over a window the app fills with any UIKit content — normally a map.
Similar App Store mirroring apps (e.g. "Screencast • mirroring for car") are listed under the
**Navigation** category. So the very likely setup is:

1. App holds the CarPlay **navigation entitlement** (granted by Apple via the CarPlay entitlement request).
2. In `templateApplicationScene(_:didConnect:to window:)` it puts an `AVPlayerLayer` / `AVSampleBufferDisplayLayer`
   (or VLCKit's drawable view) into the `CPWindow` instead of a map.
3. A `CPMapTemplate` on top provides the buttons (play/pause, channel up/down, etc.), which also handle knob/touchpad cars.
4. Mirror frames from the ReplayKit extension reach the main app (App Group / shared memory / socket)
   and are enqueued into an `AVSampleBufferDisplayLayer` in that window.

**Not confirmed** — needs checking by pulling the IPA on a Mac (`ipatool download` → `codesign -d --entitlements :- CarTV.app`)
and looking for `com.apple.developer.carplay-maps`. Using a navigation entitlement for video goes against Apple's
CarPlay guidelines, so it carries **review and removal risk**, even though these apps got through review.

## Apple's official route (new — iOS 27, WWDC26)
- New **CarPlay video app** entitlement `com.apple.developer.carplay-video`.
- Video plays **only when parked, and only in supported vehicles**; requires **AirPlay video streaming** support in the app.
- When the car says video isn't available (e.g. driving), playback continues **audio-only**.
- New templates/APIs: `CPPlaybackConfiguration` (preferredPresentation video/audio, elapsedTime, duration,
  playbackAction), portrait/landscape list images, card thumbnails with progress overlays, a Details header and a MiniPlayer.
- Recommendation from Apple: hold **both** audio and video entitlements so the app always appears.
- Limits: only cars that support it, and Apple must grant the entitlement (DLNA receive/mirroring may not fit its criteria).

## Implications for CarPlayTV
- Feature parity with CarTV is achievable as an **App Store** app — sideloading/private APIs are not required.
- Build the car display as a pluggable backend:
  - **NavCanvasBackend** — CarTV's approach (CPWindow + CPMapTemplate controls). Works on any CarPlay car, iOS 18+. Review risk.
  - **CarPlayVideoBackend** — official iOS 27 video entitlement + AirPlay. Low risk, supported cars only.
  - **AudioBackend** — CarPlay audio templates; fallback while driving.
- Must-match modules: M3U/Xtream/EPG parser, Jellyfin/Emby clients, AVPlayer+VLCKit player, DLNA renderer
  (SSDP + UPnP SOAP server), ReplayKit mirroring pipeline, Live Activities, health checker, Car Mode with knob focus,
  StoreKit 2 / RevenueCat paywall, 20+ localizations.
- Ways to stand out: enforce a real parked-only lock (CarTV relies on a disclaimer), EPG/TV guide, Plex, A/V sync offset
  (a requested feature in CarTV reviews — some cars, e.g. Mercedes, have audio lag), and hold the iOS 27 video entitlement as well.
