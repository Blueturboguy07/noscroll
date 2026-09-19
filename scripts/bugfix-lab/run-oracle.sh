#!/usr/bin/env bash
# Dispatcher for the bugfix-lab emulator step. The emulator-runner action hands
# its `script:` input to `sh -c` in a way that mangles multi-line shell, so the
# mode switch lives here instead of in the workflow YAML.
#
# The default mode, "guide", walks the GUIDE-INSTALLER path: it reads the
# rendered publik install guide committed at
# scripts/bugfix-lab/rendered-guide-android.json (produced verbatim by
# `npx tsx ~/bugfix-lab/bin/render-guide.mts noscroll android --json` from a
# publik worktree) and makes the simulated reader do what that guide says --
# nothing more. It is therefore SENSITIVE to the guide's real content: with the
# v8 rendering committed it returns PRESENT, with the v9 rendering (which adds
# the missing "Turn on NoScroll's Accessibility Service" step) it returns
# ABSENT, and nothing else about the harness changes between the two.
#
# Rounds 1-2 of this cluster hard-coded that decision (NOSCROLL_SKIP_A11Y_GRANT=1
# pinned into this mode) instead, which made the default oracle path permanently
# insensitive to the fix; VERIFY round 2 rejected the fix for exactly that
# reason ("no commit in either repo can move this default oracle path off exit
# 1"). Do not hard-code it again. The standing v8 negative control that the
# pinned flag used to provide is preserved, unchanged in meaning, as mode
# guide-v8-frozen below.
set -uo pipefail
MODE="${BUGFIX_LAB_MODE:-prefs}"
echo "bugfix-lab mode: $MODE"
case "$MODE" in
  prefs)
    bash scripts/bugfix-lab/noscroll-android-blocking-not-active.sh
    ;;
  behavior)
    # Generous control: grant the permission regardless of any guide text, and
    # restart the way rounds 1-2 did (force-stop). Isolates guide text from app
    # code; unchanged in meaning from the REPRODUCE stage.
    NOSCROLL_A11Y=grant NOSCROLL_RESTART=force-stop \
      bash scripts/bugfix-lab/noscroll-android-blocking-behavior.sh
    ;;
  guide)
    # THE ORACLE'S DEFAULT. Guide-installer path, driven by the committed
    # rendering of publik's Android guide, and "restarting phone" performed as
    # the reporter described it -- a real device reboot, not `am force-stop`.
    NOSCROLL_A11Y=guide NOSCROLL_RESTART=reboot \
      bash scripts/bugfix-lab/noscroll-android-blocking-behavior.sh
    ;;
  guide-nostop)
    # The same guide-driven path cut down to REGION.json's minimal_repro:
    # install, launch once, no restart, then open a shielded app once.
    NOSCROLL_A11Y=guide NOSCROLL_RESTART=none \
      bash scripts/bugfix-lab/noscroll-android-blocking-behavior.sh
    ;;
  guide-v8-frozen)
    # Standing negative control available from ANY commit: the same harness
    # reading a frozen copy of the v8 rendering (the guide Android installers
    # actually have today, sourceCommit 7d1c27ae...). Proves the default mode's
    # PRESENT result tracks the guide's content and not the emulator, the build
    # or the harness. This is the role the old hard-coded
    # NOSCROLL_SKIP_A11Y_GRANT=1 line in mode "guide" used to play.
    NOSCROLL_A11Y=guide NOSCROLL_RESTART=reboot \
      NOSCROLL_GUIDE_JSON=scripts/bugfix-lab/rendered-guide-android-v8-frozen.json \
      bash scripts/bugfix-lab/noscroll-android-blocking-behavior.sh
    ;;
  guide-v9)
    # FIX round 1's mode, kept so its runs (35448517323) stay reproducible:
    # permission granted unconditionally + force-stop restart. Returns PRESENT
    # because of a SEPARATE, still-open lead (an AccessibilityService that is
    # not re-bound after `am force-stop`), not because of the guide.
    NOSCROLL_A11Y=grant NOSCROLL_RESTART=force-stop \
      bash scripts/bugfix-lab/noscroll-android-blocking-behavior.sh
    ;;
  guide-v9-nostop)
    # FIX round 2's mode, kept so run 35449459772 stays reproducible.
    NOSCROLL_A11Y=grant NOSCROLL_RESTART=none \
      bash scripts/bugfix-lab/noscroll-android-blocking-behavior.sh
    ;;
  *)
    echo "HARNESS_ERROR: unknown mode $MODE"
    echo "BUGFIX_LAB_UNRUNNABLE"
    exit 2
    ;;
esac
