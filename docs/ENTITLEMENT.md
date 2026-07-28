# The FamilyControls entitlement is the critical path

`com.apple.developer.family-controls` is gated by Apple. It requires written justification, takes
days-to-weeks, and **can be denied**. Request it before writing shield code, not after — it must
be granted for the main app **and each of the three extensions**:

- `ShieldConfigurationExtension`
- `ShieldActionExtension`
- `DeviceActivityMonitorExtension`

## Justification to submit

> NoScroll is an open-source digital-wellbeing app. At the user's own request it shields social
> media apps the user selects themselves, so that the user reaches a stripped-down version of the
> same service without short-form video feeds. All configuration is local to the device; there is
> no backend, no remote management, and no third party can change a user's settings. Source:
> <repo URL>.

Being open source helps — link the repository.

## If it is denied

The app degrades to wrapper-only. That is a supported state, not a crash:

- `ShieldController.authorization` becomes `.denied`.
- The promise changes from "blocked" to "a calmer way in", **in the copy, honestly**. Do not claim
  enforcement the build cannot deliver — that is both a lie to users and an App Review risk.
- Ship a documented manual path: Screen Time → App Limits, configured by the user.

Planning for this now makes a denial cost a week rather than a rewrite.

## Android equivalent

`BIND_ACCESSIBILITY_SERVICE` needs a Play Permission Declaration Form. The 28 Jan 2026 policy
tightening bans autonomous "initiate, plan, execute actions" uses but explicitly carves out:

> "deterministic, rule-based automation ... a static, human-defined script (for example, 'If
> Trigger X occurs, perform Action Y')"

Quote that sentence in the declaration. `ForegroundAppMonitor` is written to sit inside it: it
reads one field (the foreground package name), performs no action inside any other app, and
declares neither `canRetrieveWindowContent` nor `canPerformGestures`.
