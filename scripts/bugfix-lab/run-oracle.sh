#!/usr/bin/env bash
# Dispatcher for the bugfix-lab emulator step. The emulator-runner action hands
# its `script:` input to `sh -c` in a way that mangles multi-line shell, so the
# mode switch lives here instead of in the workflow YAML.
set -uo pipefail
MODE="${BUGFIX_LAB_MODE:-prefs}"
echo "bugfix-lab mode: $MODE"
case "$MODE" in
  prefs)
    bash scripts/bugfix-lab/noscroll-android-blocking-not-active.sh
    ;;
  behavior)
    bash scripts/bugfix-lab/noscroll-android-blocking-behavior.sh
    ;;
  guide)
    # This mode reproduces the ORIGINAL bug: publik lib/guides/noscroll.ts v8's
    # Android branch never asked the reader to grant Accessibility, so a
    # guide-installer following it never does. Kept exactly as REPRODUCE/
    # MINIMIZE left it, as a standing negative control that the bug was real
    # -- do not edit this case. See mode=guide-v9 for the FIX round's oracle.
    NOSCROLL_SKIP_A11Y_GRANT=1 bash scripts/bugfix-lab/noscroll-android-blocking-behavior.sh
    ;;
  guide-v9)
    # bugfix-lab FIX round (cluster noscroll-android-blocking-not-active):
    # publik's noscroll Android guide was re-rendered from lib/guides/
    # noscroll.ts v9 (fix/noscroll-android-blocking-not-active, publik commit
    # f37e392) and now DOES instruct the reader to turn on NoScroll's
    # Accessibility Service, via a new "enable-accessibility" step between
    # "run" and "verify" -- see $WORK/publik/lib/guides/noscroll.ts for the
    # exact rendered text. A guide-installer who follows this branch to the
    # end therefore grants the permission before finishing the guide, so this
    # mode does too. This is a resync of the harness's simulated
    # guide-installer input to the guide's current (fixed) content, not a
    # change to how PRESENT/ABSENT is decided -- still: does the shielded
    # app's foreground window read app.noscroll/.shield.ShieldActivity after
    # the same steps noscroll-android-blocking-behavior.sh has always run
    # (including the force-stop+relaunch step, unchanged, which models the
    # report's own "restarting phone, pairing the phone again").
    bash scripts/bugfix-lab/noscroll-android-blocking-behavior.sh
    ;;
  *)
    echo "HARNESS_ERROR: unknown mode $MODE"
    echo "BUGFIX_LAB_UNRUNNABLE"
    exit 2
    ;;
esac
