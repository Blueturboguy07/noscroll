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
    NOSCROLL_SKIP_A11Y_GRANT=1 bash scripts/bugfix-lab/noscroll-android-blocking-behavior.sh
    ;;
  behavior-nostop)
    NOSCROLL_SKIP_RESTART=1 bash scripts/bugfix-lab/noscroll-android-blocking-behavior.sh
    ;;
  *)
    echo "HARNESS_ERROR: unknown mode $MODE"
    echo "BUGFIX_LAB_UNRUNNABLE"
    exit 2
    ;;
esac
