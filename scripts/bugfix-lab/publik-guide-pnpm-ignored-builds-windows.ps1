# Oracle body for cluster publik-guide-pnpm-ignored-builds-windows (NoScroll half).
#
# Reproduces exactly what the guide has the reader type on Windows (rendered
# from lib/guides/noscroll.ts via render-guide.mts), against a caller-supplied
# commit (defaults to the guide's current sourceCommit). Does NOT touch pnpm
# version -- installs pnpm the same way the guide does (`npm install -g pnpm`),
# which is what actually determines whether the ignored-builds gate applies.
#
# Prints BUGFIX_LAB_PRESENT and exits 1 if the engine-deps step fails with
# ERR_PNPM_IGNORED_BUILDS (or any non-zero exit). Prints BUGFIX_LAB_ABSENT and
# exits 0 if it completes and the esbuild binary actually landed.

param(
  [string]$PinSha = "7d1c27ae8e11c551c1c11f82125a29b3f9bbf505"
)

$ErrorActionPreference = "Continue"
Write-Host "=== pnpm version installed by the guide's own step ==="
npm.cmd install -g pnpm
pnpm.cmd --version

Write-Host "=== checkout pinned commit $PinSha ==="
git checkout $PinSha
if ($LASTEXITCODE -ne 0) {
  Write-Host "BUGFIX_LAB_ABSENT (oracle setup failure: checkout failed, not a repro)"
  exit 2
}

Write-Host "=== pnpm.cmd install --dir engine (verbatim guide step 7) ==="
pnpm.cmd install --dir engine 2>&1 | Tee-Object -Variable installOutput
$installExit = $LASTEXITCODE
$installOutput | Write-Host

$ignoredBuilds = ($installOutput -join "`n") -match "ERR_PNPM_IGNORED_BUILDS"

if ($installExit -ne 0 -or $ignoredBuilds) {
  Write-Host "EVIDENCE: pnpm install --dir engine exited $installExit, ERR_PNPM_IGNORED_BUILDS matched=$ignoredBuilds"
  Write-Host "BUGFIX_LAB_PRESENT"
  exit 1
}

# Functional check: esbuild's own binary must actually run, not just "exit 0
# while quietly skipping the build script" (pnpm can report success while
# leaving a package's postinstall un-run).
Write-Host "=== pnpm.cmd --dir engine exec esbuild --version ==="
pnpm.cmd --dir engine exec esbuild --version 2>&1 | Tee-Object -Variable esbuildOutput
$esbuildExit = $LASTEXITCODE
$esbuildOutput | Write-Host

if ($esbuildExit -ne 0) {
  Write-Host "BUGFIX_LAB_PRESENT (install exited 0 but esbuild's own binary does not run afterward)"
  exit 1
}

Write-Host "BUGFIX_LAB_ABSENT"
exit 0
