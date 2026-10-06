# Shipping CarPlayTV to the App Store

A checklist of what has to happen outside the code before submission.

## 1. Entitlements Apple must grant (request early — approval takes weeks)

| Entitlement | Why | Where to request |
|---|---|---|
| `com.apple.developer.carplay-maps` (CarPlay navigation) | Gives the app a drawable window on the car screen; video is drawn there. | developer.apple.com/carplay → request CarPlay entitlement |
| `com.apple.developer.networking.multicast` | Receive (DLNA): answering SSDP discovery on 239.255.255.250:1900. | developer.apple.com/contact/request/networking-multicast |
| *(Phase 5)* `com.apple.developer.carplay-video` | Official iOS 27 CarPlay video app category. | developer.apple.com/carplay |

Until they're granted, a real-device build can't be signed with them. The CarPlay Simulator works without them.
To build for a device before approval, temporarily remove the entitlement from `project.yml`.

**Review risk:** using the navigation entitlement to show video is outside Apple's intended use. CarTV-type
apps are live on the store, but Apple can reject or later remove the app. Mitigations already built in:
video is paused on the car display while moving, a passengers-only notice on first launch, and the app ships no content.

## 2. App Store Connect setup
- Bundle IDs: `com.bharathkgowda.carplaytv`, `.widgets` (Live Activity), `.broadcast` (screen mirroring).
- In-app purchases (create both, then add to a subscription group for the monthly one):
  - `com.bharathkgowda.carplaytv.pro.monthly` — auto-renewable, 1 month.
  - `com.bharathkgowda.carplaytv.pro.lifetime` — non-consumable.
- Free tier: 1 source, 15 minutes of casting/mirroring per session (see `ProStore`).

## 3. Privacy
- `App/PrivacyInfo.xcprivacy` declares UserDefaults (CA92.1) and file timestamps (C617.1); no tracking.
- App Privacy label: **Data Not Collected** (no analytics, no account, no server; StoreKit is handled by Apple).
- Usage strings: location (driving lock), local network (media servers + Receive), photo library (import).
- Write and host a privacy policy URL (required) and terms of use (required for subscriptions).

## 4. Review notes to include
- How to test: a demo M3U link with freely licensed streams (e.g. Apple's sample HLS streams), plus
  how to open the app in the CarPlay Simulator.
- Explain: player only, no bundled content; video only while parked; audio continues when driving.
- `NSAllowsArbitraryLoads` is on because user-supplied IPTV and home media servers are usually plain HTTP.
- Export compliance: `ITSAppUsesNonExemptEncryption = NO` (only standard OS encryption).

## 5. Licensing
- **VLCKit is LGPL-2.1** and the SPM build links it statically. LGPL obligations for a closed-source app
  include letting users relink against a modified VLCKit (e.g. by providing object files on request) and
  shipping the license text and an offer for the VLCKit source. Get a legal review, or open-source the app.
- Add an "Acknowledgements" screen with the VLCKit/LGPL notice before release.

## 6. Still to do before submission
- App icon, launch screen and the UI design pass (Phase 4).
- Localizations.
- Screenshots (iPhone + CarPlay), app description, keywords, support URL.
- TestFlight beta on real cars (wired + wireless CarPlay, a few head-unit sizes).
