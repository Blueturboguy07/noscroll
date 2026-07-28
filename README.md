# NoScroll

**Use Instagram and YouTube without short-form video.** Free, open source, no paywall, no ads,
no analytics.

NoScroll removes Reels, Shorts, Explore and algorithmically suggested content — and keeps the
parts you actually opened the app for: messages, the people you follow, and posting. When a
friend sends you a reel you can watch *that* video. You just can't scroll to the next one.

> Status: **pre-release.** The engine, rule bundles, both native shells and the shield layers are
> written and tested. Not yet submitted to either store — see [What's not done](#whats-not-done).

---

## How it works

Two layers. The second is the one that matters.

**1. The wrapper.** NoScroll loads the platforms' own mobile websites in an embedded browser and
injects a small engine that hides or removes the endless surfaces. Your session cookies stay on
your device.

**2. The shield.** A wrapper on its own enforces nothing — you'd just open Safari. So NoScroll also
shields the real Instagram and YouTube apps at the OS level (iOS Screen Time / FamilyControls,
Android AccessibilityService), which makes the stripped version the way in rather than a
suggestion.

```
engine/    TypeScript → one 7.6 KB IIFE. The entire blocking implementation.
rules/     Signed JSON rule bundles. Data, not code — updatable without an app release.
ios/       Swift. WKWebView shell + FamilyControls + three Screen Time extensions.
android/   Kotlin. WebView shell + AccessibilityService.
probe/     Playwright smoke tests, run every 6h against live Instagram and YouTube.
tools/     Bundle signing, cross-language canonicalisation check, engine sync.
```

The engine is byte-identical on both platforms. Everything platform-specific stays in the shells.

### Rules are data

Every competitor in this category hardcodes CSS selectors and patches them reactively, which is
why they visibly leak. NoScroll ships selectors as an **ed25519-signed JSON bundle** fetched at
runtime with a three-tier fallback — remote → cached → baked into the binary — so a cold first
launch with no network still blocks, and an upstream redesign is fixed in minutes instead of an
App Store review cycle.

Every rule declares `expectMin`. The engine counts what it actually matched and reports anomalies,
so a rotted selector raises an alert before a user notices.

**Rules are open to pull requests.** If Instagram changes something and NoScroll starts leaking,
you can fix it yourself — see [docs/RULES.md](docs/RULES.md).

---

## Build

```bash
# Engine — 40 tests, no device needed
cd engine && pnpm install && pnpm test && pnpm build

# Sync the built engine + rules into both app targets
./tools/sync-engine.sh

# iOS — pure logic tests on the host
cd ios/NoScrollCore && swift test

# Android — unit tests + a real APK
cd android && gradle :app:testDebugUnitTest :app:assembleDebug

# Live probes against real Instagram and YouTube
cd probe && pnpm install && pnpm exec playwright install chromium && pnpm probe
```

Rule bundles are signed. To work on them you need your own keypair:

```bash
node tools/sign-bundle.mjs keygen           # writes keys/ (gitignored)
node tools/sign-bundle.mjs sign rules/*.json
swift tools/verify-canonical.swift          # Node and Swift must agree byte for byte
```

---

## Nothing is forced on

Every block is a switch you own. The core ones — Reels, Shorts, Explore,
suggested posts — arrive switched **on**, so a fresh install works with no
setup, and first-run onboarding shows you every switch once so nothing is a
surprise later. But you can turn any of them off, at any time, in Settings.

The product has an opinion. It doesn't take the choice away.

## The one rule that is not negotiable

```
The engine MUST NOT hide, remove, restyle, or observe any node on an auth surface.
```

Hard-coded in [`engine/src/authguard.ts`](engine/src/authguard.ts), not overridable by any rule
bundle, and enforced by a CI test that fails the build.

Two reasons. A hiding rule that swallows Instagram's own security interstitial bricks login with
no visible error. And Apple 5.1.1(vi) treats credential harvesting as *developer-program removal*
— refusing to look at a login page at all is what keeps NoScroll provably clear of it.

Verified against the real login page by the live probe, not just in a test DOM.

---

## Privacy

Two tiers, stated precisely, because vagueness here is what makes people call a wrapper a phishing
app:

1. **Platform session cookies never leave your device.** There is no backend, no proxy, and no
   server-side cache of anything you look at. The repo is public, so this is auditable rather than
   a promise.
2. **Rule-health telemetry is opt-in and anonymous.** It reports `{ruleId, expected, actual,
   bundleVersion}` — never a URL, never page content. See
   [`engine/src/bridge.ts`](engine/src/bridge.ts).

No analytics SDK. No ad pixel. No crash reporter carrying identifiers. No tracking on the website
or the legal pages.

Full detail: [docs/PRIVACY.md](docs/PRIVACY.md).

---

## What's not done

Honestly, because a feature list that overpromises is the thing this project is reacting to:

- **Not submitted to either store.** The iOS `com.apple.developer.family-controls` entitlement is
  gated by Apple, takes days-to-weeks, and can be denied — see [docs/ENTITLEMENT.md](docs/ENTITLEMENT.md).
  It has to be granted before the shield layer can run on a device.
- **No Xcode project file yet.** Sources compile against the iOS SDK; the `.xcodeproj` with three
  extension targets and the app group still needs to be assembled.
- **Android rule-bundle signature verification is not implemented.** iOS verifies; Android
  currently reads bundles from assets/cache without checking the signature. Do not ship without it.
- **No notifications.** WKWebView cannot receive web push, and shielding an app suppresses that
  app's own notifications too. This is a scoped-out non-goal, not a bug.
- **Instagram and YouTube only.** Six other services would be six other route maps; two done
  properly beats eight half-broken.
- **Posting Reels, stories, DM media, calls** — not available on the mobile web, so not available
  here. Post Mode temporarily lifts the shield so you can post in the real app.
- **The logged-in probe is skipped** unless you supply `PROBE_IG_STATE`. Use a dedicated probe
  account, never a personal one.

---

## Licence

AGPL-3.0-or-later. See [LICENCE](LICENSE).

Rule bundles seeded from MIT-licensed filter lists — `gijsdev/ublock-hide-yt-shorts` and
`BevizLaszlo/UBlock-Filters-for-Social-Media` — with provenance recorded per rule.

NoScroll is not affiliated with, endorsed by, or connected to Meta, Instagram, Google or YouTube.
