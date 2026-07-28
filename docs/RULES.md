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

## Defaults, not locks

No surface is locked — every block is a switch the user owns, enforced by
`engine/test/rulelint.test.ts`. The product's opinion lives in `defaultEnabled`:
the core blocks ship `true` so a fresh install works with no setup, and the
extras ship `false`.

Surfaces that share a `label` are presented as **one** switch in the apps and
toggle together. That is how "Block Reels" covers both the DOM rule (the nav
icon) and the route rule (typing the URL) without showing the user two rows —
`(routes)` is an implementation detail and has no business on screen.

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
