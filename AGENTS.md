# AGENTS.md

## publik API
- Base URL: https://publikhq.com/api/v1 (OpenAI Chat Completions, Responses, Anthropic Messages)
- Models: publik-fast, publik-balanced, publik-smart only; never a vendor model name
- Sign in with publik: the publik module's gate runs at start-up, before the first screen; it also sends usage telemetry
- Key: per-install `pk_` from POST /installs, stored at the publik credential path; env PUBLIK_API_KEY / PUBLIK_API_BASE_URL override (test builds only, see "Test hooks")
- App token: publik-app-token.txt (public by design, committed) or PUBLIK_APP_TOKEN
- 402: show error.message plus error.top_up_url only
- Never print or log a key
- Docs: https://publikhq.com/llms.txt, https://publikhq.com/developers, https://publikhq.com/skills/api.md

## publik in this repo
- NoScroll calls no AI model: `usesAI = false` (iOS) and `USES_AI = false` (Android). The gate shows Sign in with publik only.
- Gate mode, one build setting: `PUBLIK_GATE_MODE = required | optional` (default `required`). iOS: `ios/Config/App.xcconfig` → Info.plist key `PublikGateMode` (override: `xcodebuild ... PUBLIK_GATE_MODE=optional`). Android: `PUBLIK_GATE_MODE` env or `-PpublikGateMode=optional` → `BuildConfig.PUBLIK_GATE_MODE`. Optional mode: no wall, "Sign in with publik" in Settings (iOS) / Status (Android), usage counting only after sign-in.
- Display name: `APP_DISPLAY_NAME` in `ios/Config/App.xcconfig` (app, widget, purpose strings, in-app text via `AppState.appName`). Android: `app_name` in `strings.xml`.
- iOS: `ios/NoScroll/Publik/Publik.swift` (the module) and `PublikGateView.swift` (its SwiftUI screen and the Settings rows: sign out, delete account, usage counting). `NoScrollApp` in `ios/NoScroll/App/RootView.swift` shows the gate before `RootView` in required mode. Privacy manifest: `ios/NoScroll/PrivacyInfo.xcprivacy`.
- Android: `android/app/src/main/java/app/noscroll/publik/Publik.kt` (a Kotlin port of the module), `PublikGateView.kt` and `PublikSignInActivity.kt` (optional mode). `MainActivity.onCreate` runs the gate before `startApp()` in required mode. `StatusActivity` has the publik rows.
- App token: the "publik app token" build phase (iOS) and `app/build.gradle.kts` (Android) take `PUBLIK_APP_TOKEN` at build time, else `publik-app-token.txt` at the repo root. CI uses the repo secret `PUBLIK_APP_TOKEN`. A release build without a `pat_` token fails: iOS `CONFIGURATION=Release` (the build phase exits 1), Android `preReleaseBuild` (task `checkPublikAppToken`). Debug builds only warn.
- Test hooks: iOS reads `PUBLIK_API_BASE_URL`, `PUBLIK_ORIGIN`, `PUBLIK_TELEMETRY_URL`, `PUBLIK_API_KEY`, `PUBLIK_APP_TOKEN`, `PUBLIK_SELF_TEST`, `PUBLIK_TEST_PRESS` (the gate presses that button once by itself) and `PUBLIK_LAYOUT_PROBE` (the first onboarding screen prints its layout, then the app exits) from the environment or launch arguments only when the Swift flag `PUBLIK_TEST_HOOKS` is on. It is on in Debug and in CI test builds (`xcodebuild ... PUBLIK_TEST_HOOKS=YES`), and off in the App Store Release build (`ios/Config/App.xcconfig`). Android reads the `PUBLIK_` intent extras only when `BuildConfig.DEBUG`.
- Sign out (both systems): stop usage counting, delete the key file first, then revoke the key held in memory in a task that no screen can cancel. iOS excludes the publik folder and the key file from backups. Android has `allowBackup="false"`. Android keeps `Publik.signedInThisProcess`, so a recreated `MainActivity` does not show the gate again.
- Self-test of a built app: iOS Simulator `SIMCTL_CHILD_PUBLIK_SELF_TEST=1 xcrun simctl launch --console-pty booted app.noscroll`; Android `adb shell am start -n app.noscroll/.MainActivity --es PUBLIK_SELF_TEST 1`, then `adb logcat -d -s publik`. It prints `publik self-test: ok noscroll <version>`.
- Test publik: `PUBLIK_API_BASE_URL` (iOS test-hook builds: environment or launch argument `-PUBLIK_API_BASE_URL <url>`; Android debug builds: `--es PUBLIK_API_BASE_URL <url>`).
- iOS screens: `AppRoot` (`ios/NoScroll/App/RootView.swift`) is the one stable root view. The gate, the onboarding and the tabs are content inside it (no root view controller swap, no `fullScreenCover`). The gate hands over only after its in-app browser has closed completely. `.github/scripts/ios-gate-layout-test.sh` checks this in CI with a fake publik (`.github/scripts/fake-publik.py`).
- Offline start (iOS): the key file keeps a "signed in" mark (`claimed`) and the handle. With the mark, the gate passes when publik does not answer (offline, 5xx, 408, 429, a captive portal). Only publik's JSON 401 or a wallet that is not claimed clears it. A fresh install needs publik once.
- iOS appearance: light only (`UIUserInterfaceStyle = Light`), on purpose.
- `.github/workflows/publik-test-builds.yml` builds the test artifacts `ios-sim-app` (required mode), `ios-sim-app-optional` (optional mode) and `android-debug-apk`, and runs the self-tests.
