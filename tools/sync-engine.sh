#!/usr/bin/env bash
# Rebuild the engine and copy it + the rule bundles into both app targets.
# Both shells MUST carry the identical engine bundle — that is the architecture.
set -euo pipefail
cd "$(dirname "$0")/.."
(cd engine && pnpm build)
mkdir -p android/app/src/main/assets/rules ios/NoScroll/Resources/Rules
cp engine/dist/noscroll.js android/app/src/main/assets/noscroll.js
cp engine/dist/noscroll.js ios/NoScroll/Resources/noscroll.js
cp rules/*.json android/app/src/main/assets/rules/
cp rules/*.json ios/NoScroll/Resources/Rules/
echo "engine + rules synced to both shells ($(wc -c < engine/dist/noscroll.js) bytes)"
