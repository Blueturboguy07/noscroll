#!/usr/bin/env python3
"""Read the rendered publik install guide and report what it tells the reader to do.

The harness stands in for a human guide-installer. Turning on an Android
AccessibilityService is an OS permission that only a person can grant -- no app
code, build step or CI action can set it for them -- so the only honest
question CI can ask is: *does the guide this reader is holding tell them to
turn it on?*  If it does, the simulated reader goes and does it; if it does
not, the simulated reader never does, because they were never told it existed.
Either way the VERDICT is still measured on the emulator afterwards (does
NoScroll's shield actually cover a shielded app) -- this file only decides what
the person following the guide does, never whether the bug is present.

Input: the output of
    npx tsx ~/bugfix-lab/bin/render-guide.mts noscroll android --json
run from a publik worktree, committed here as rendered-guide-android.json.
That file is the guide's user-visible content, not NoScroll's source; the
harness never inspects app code or diffs to reach its verdict.

Prints the step list, then one machine-readable line:
    A11Y_STEP: <step number> <step id>      (the guide does tell them)
    A11Y_STEP: NONE                         (it does not)
"""
import json
import re
import sys

SERVICE = re.compile(r"accessib", re.I)
TURN_ON = re.compile(
    r"\b(turn(s|ing)?\s+(it|them|this|on)|turn\s+\w+\s+on|enable|enabling|switch\s+(it\s+)?on|allow)\b",
    re.I,
)

def main(path: str) -> int:
    with open(path) as fh:
        guide = json.load(fh)
    steps = guide.get("steps") or []
    print(f"rendered guide: {guide.get('slug')} v{guide.get('version')} "
          f"({guide.get('platform')}), sourceCommit {guide.get('sourceCommit')}, "
          f"{len(steps)} steps")
    hit = None
    for s in steps:
        text = " ".join(str(s.get(k) or "") for k in
                        ("title", "body", "verifierLabel", "command"))
        tells = bool(SERVICE.search(text) and TURN_ON.search(text))
        print(f"  step {s.get('n')} [{s.get('kind')}] {s.get('id')}: {s.get('title')}"
              + ("   <-- tells the reader to turn the accessibility service on" if tells else ""))
        if tells and hit is None:
            hit = s
    print(f"A11Y_STEP: {hit['n']} {hit['id']}" if hit else "A11Y_STEP: NONE")
    return 0

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: guide-reader.py <rendered-guide.json>", file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1]))
