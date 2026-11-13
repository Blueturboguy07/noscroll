# AGENTS.md

## publik API
- Base URL: https://publikhq.com/api/v1 (OpenAI Chat Completions, Responses, Anthropic Messages)
- Models: publik-fast, publik-balanced, publik-smart only; never a vendor model name
- Sign in with publik: the publik module's gate runs at start-up, before the first screen; it also sends usage telemetry
- Key: per-install `pk_` from POST /installs, stored at the publik credential path; env PUBLIK_API_KEY / PUBLIK_API_BASE_URL override
- App token: publik-app-token.txt (public by design, committed) or PUBLIK_APP_TOKEN
- 402: show error.message plus error.top_up_url only
- Never print or log a key
- Docs: https://publikhq.com/llms.txt, https://publikhq.com/developers, https://publikhq.com/skills/api.md

## publik in this repo
- NoScroll calls no AI model: `usesAI = false` (iOS) and `USES_AI = false` (Android). The gate shows Sign in with publik only.
- iOS: `ios/NoScroll/Publik/Publik.swift` (the module) and `PublikGateView.swift` (its SwiftUI screen). `NoScrollApp` in `ios/NoScroll/App/RootView.swift` shows the gate before `RootView`.
- Android: `android/app/src/main/java/app/noscroll/publik/Publik.kt` (a Kotlin port of the module) and `PublikGateView.kt`. `MainActivity.onCreate` runs the gate before `startApp()`.
- App token: the "publik app token" build phase (iOS) and `app/build.gradle.kts` (Android) take `PUBLIK_APP_TOKEN` at build time, else `publik-app-token.txt` at the repo root. CI uses the repo secret `PUBLIK_APP_TOKEN`.
- Self-test of a built app: iOS Simulator `SIMCTL_CHILD_PUBLIK_SELF_TEST=1 xcrun simctl launch --console-pty booted app.noscroll`; Android `adb shell am start -n app.noscroll/.MainActivity --es PUBLIK_SELF_TEST 1`, then `adb logcat -d -s publik`. It prints `publik self-test: ok noscroll <version>`.
- Test publik: `PUBLIK_API_BASE_URL` (iOS: environment or launch argument `-PUBLIK_API_BASE_URL <url>`; Android debug builds: `--es PUBLIK_API_BASE_URL <url>`).
- `.github/workflows/publik-test-builds.yml` builds the test artifacts `ios-sim-app` and `android-debug-apk` and runs both self-tests.
