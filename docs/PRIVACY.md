# Privacy

Stated in two tiers, precisely, because vagueness here is exactly what makes users call a wrapper
a phishing app.

## Tier 1 — your session, on your device

Platform session cookies are stored locally and **never transmitted anywhere**.

- iOS: a per-account `WKWebsiteDataStore(forIdentifier:)`.
- Android: `CookieManager` is process-global, so accounts are isolated by
  `SessionCookieJar` (save → clear → restore on switch).

There is no backend. No proxy. No server-side cache of anything you look at. The repository is
public, so this is auditable rather than a promise.

## Tier 2 — rule-health telemetry, opt-in

Off by default. When on, a message contains exactly:

```json
{ "ruleId": "instagram.reels-tab", "expected": 1, "actual": 0, "bundleVersion": 42 }
```

Never a URL. Never page content. Never an identifier. Enforced in `engine/src/bridge.ts`, where
diagnostic message types are gated on the opt-in flag.

## What is not present

- No analytics SDK.
- No advertising pixel — including on the website's legal pages.
- No crash reporter carrying identifiers.
- No "hours saved" counter that is not computed from real blocked-event counts.

## Store declarations

Apple App Privacy and Google Play Data Safety must be filled in from an **actual SDK inventory**,
must match each other, and must match the code. Declaring "no data collected" on one store while
declaring tracking identifiers on the other is a policy violation, not a rounding error.

## The login flow, explained before it happens

You sign in on the platform's own web page, inside the app. Onboarding says so up front:

- It is Instagram's / YouTube's real login page, not a NoScroll form.
- NoScroll never reads, writes, or observes anything on it — see `engine/src/authguard.ts`.
- A security checkpoint on first sign-in is expected and normal: it is a new browser to them.
