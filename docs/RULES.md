# Writing rules

Rules are **data**. You can fix NoScroll without touching Swift, Kotlin, or the engine.

## Selector policy, in priority order

1. `href` patterns — `a[href^="/reels"]`. Most stable.
2. ARIA — `[aria-label="Reels"]`, `[role="tablist"]`.
3. SVG `<title>` text, icon path prefixes.
4. Structural position inside a stable landmark.
5. Hashed classes — **only** with `expiresAfter`, which forces a review date.

**Never match on visible text.** It breaks across all seven locales.

**Never use `:has(> ...)`.** The relative form is valid in browsers but unsupported by the DOM
engine the golden fixtures run in, so such a rule silently matches nothing in CI and ships
untested. Write `:has(parent > child)` instead. Enforced by `engine/test/rulelint.test.ts`.

## Rule kinds

| kind | use for |
|---|---|
| `route-rewrite` | `/shorts/<id>` → `/watch?v=<id>`. Cheapest and most robust. |
| `route-block` | whole surfaces with a real URL (`/reels/`, `/explore/`). |
| `dom-remove` | everything with no URL — suggested posts, shelves, nav icons. |
| `isolate` | single-item routes that must not advance to a next item. |
| `style` | grayscale and similar. |

Content that arrives via background GraphQL with **no URL change** (Instagram's suggested posts)
can only be handled by `dom-remove` with `"observe": true`. No quantity of route rules will help.

## Probes

Every rule should declare one:

```jsonc
"probe": { "expectMin": 1, "onlyWhenSignedIn": true }
```

`expectMin > 0` means "this must match something, or the selector has rotted". Use
`onlyWhenSignedIn` when the surface does not exist for a logged-out visitor — logged-out
m.youtube.com has three pivot-bar items and no Shorts tab, so a zero there is correct.

## Locked surfaces

`"locked": true` means the user cannot switch it off. That is deliberate and it is the product's
spine: Block Reels, Block Explore and Block Shorts are always on, so there is no "I'll just turn
it off for a second" failure mode. Everything else is an optional toggle.

## Never target an auth surface

CI will fail. See `engine/src/authguard.ts`.

## Workflow

```bash
vim rules/instagram.json
cd engine && pnpm test          # golden fixtures + lint + auth invariant
node tools/sign-bundle.mjs sign rules/instagram.json
swift tools/verify-canonical.swift
cd probe && pnpm probe          # against the live site
```
