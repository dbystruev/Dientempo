#!/usr/bin/env bash
set -euo pipefail

# Dientempo build.sh — modeled on PlantIdentify-iOS/scripts/build.sh
# Usage: ./scripts/build.sh beta   (builds com.bystruev.dientempo → TestFlight)
#
# Uses the SAME App Store Connect API key as PlantIdentify (CDCJAGN567, team
# 8J39KF9DMS "Human Rated AI") — ASC API keys are scoped to the whole team,
# not a single app, and this key already has visibility into all of the
# team's apps including Dientempo (App Store Connect app id 6780648670). No
# new key was needed; see fastlane/Fastfile for details, and the bottom of
# this file for what to do if that ever stops being true.
#
# Build numbering: unlike PlantIdentify (sequential integers), Dientempo's
# project already uses date-based build numbers (CURRENT_PROJECT_VERSION =
# "2026.06.30" style, i.e. `date +%F` with dots). This script preserves that
# convention rather than switching schemes: it sets today's date as the
# build number, and only bumps forward from the latest TestFlight build if
# building twice on the same day would otherwise produce a non-increasing
# (rejected) build number.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: $(basename "$0") beta"
  echo "  beta — build com.bystruev.dientempo and upload to TestFlight (via fastlane)"
  exit 0
fi

TARGET="${1:-beta}"
if [[ "$TARGET" != "beta" && "$TARGET" != "all" ]]; then
  echo "Unknown target: $TARGET (only 'beta' supported)" >&2
  exit 1
fi

echo "Dientempo → com.bystruev.dientempo (team 8J39KF9DMS, key CDCJAGN567)"
echo "Project: $PROJECT_ROOT"

# Prefer brew fastlane to avoid rbenv digest-crc issue
if [[ -x "/opt/homebrew/bin/fastlane" ]]; then
  FASTLANE_BIN="/opt/homebrew/bin/fastlane"
elif command -v fastlane >/dev/null 2>&1; then
  FASTLANE_BIN="$(command -v fastlane)"
else
  echo "fastlane not found" >&2
  exit 1
fi

# Resolve the next date-based build number (YYYY.MM.DD).
# Take today's date unless it would collide with (be <= than) the latest
# build already on TestFlight, in which case bump the day component forward
# so the build number still strictly increases as TestFlight requires.
echo "Resolving next build number..."
TODAY="$(date +%F | tr '-' '.')"   # e.g. 2026.09.05
LATEST_BUILD="$("$FASTLANE_BIN" latest_build_number 2>/dev/null | sed -n 's/^LATEST_BUILD=//p' || true)"

version_ge() {
  # Returns 0 (true) if $1 >= $2, comparing YYYY.MM.DD numerically component-by-component.
  local a1 a2 a3 b1 b2 b3
  IFS='.' read -r a1 a2 a3 <<< "$1"
  IFS='.' read -r b1 b2 b3 <<< "$2"
  a1=${a1:-0}; a2=${a2:-0}; a3=${a3:-0}
  b1=${b1:-0}; b2=${b2:-0}; b3=${b3:-0}
  if (( 10#$a1 != 10#$b1 )); then (( 10#$a1 > 10#$b1 )); return; fi
  if (( 10#$a2 != 10#$b2 )); then (( 10#$a2 > 10#$b2 )); return; fi
  (( 10#$a3 >= 10#$b3 ))
}

if [[ -z "$LATEST_BUILD" ]]; then
  NEXT_BUILD="$TODAY"
elif version_ge "$TODAY" "$LATEST_BUILD" && [[ "$TODAY" != "$LATEST_BUILD" ]]; then
  NEXT_BUILD="$TODAY"
else
  # Today's date is <= the latest build already on TestFlight (either building
  # again same day, or clock skew) — bump the day component forward by 1 to
  # guarantee a strictly increasing build number. Not a real calendar date at
  # that point, just a monotonic counter dressed as one.
  IFS='.' read -r y m d <<< "$LATEST_BUILD"
  d=$((10#$d + 1))
  NEXT_BUILD="$(printf '%s.%s.%02d' "$y" "$m" "$d")"
fi
echo "Latest on TestFlight: ${LATEST_BUILD:-(none)} · Today: $TODAY · Using: $NEXT_BUILD"

echo "Setting CURRENT_PROJECT_VERSION → $NEXT_BUILD"
python3 - "$NEXT_BUILD" << 'PYEOF'
import re, sys

new_version = sys.argv[1]
path = "Dientempo.xcodeproj/project.pbxproj"
with open(path) as f:
    content = f.read()

# Walk each XCBuildConfiguration block; only touch the ones that build the
# Dientempo APP target (PRODUCT_BUNDLE_IDENTIFIER = com.bystruev.dientempo;),
# not the DientempoTests target's own (unrelated) build number.
pattern = re.compile(
    r"(isa = XCBuildConfiguration;\s*buildSettings = \{.*?\};)",
    re.DOTALL
)

def replace_block(match):
    block = match.group(1)
    if "PRODUCT_BUNDLE_IDENTIFIER = com.bystruev.dientempo;" not in block:
        return block
    return re.sub(
        r"CURRENT_PROJECT_VERSION = [^;]+;",
        f"CURRENT_PROJECT_VERSION = {new_version};",
        block
    )

new_content, count = pattern.subn(replace_block, content)
changed = new_content != content
with open(path, "w") as f:
    f.write(new_content)

if not changed:
    print("WARNING: no CURRENT_PROJECT_VERSION was updated — check project.pbxproj structure", file=sys.stderr)
    sys.exit(1)
print(f"project.pbxproj updated to CURRENT_PROJECT_VERSION = {new_version}")
PYEOF

echo "Running $FASTLANE_BIN beta..."
"$FASTLANE_BIN" beta
BETA_STATUS=$?
if [[ $BETA_STATUS -ne 0 ]]; then
  echo "fastlane beta failed with status $BETA_STATUS — skipping expire/commit" >&2
  exit $BETA_STATUS
fi

# Expire old TestFlight builds, keeping latest + externally approved / public link.
# Non-fatal: build is already uploaded, expire failure should not fail the script.
echo "Expiring old TestFlight builds (keeping latest + external)..."
"$FASTLANE_BIN" expire_old_builds || echo "Warning: expire_old_builds failed — check manually" >&2

# Stage/commit/push code changes (never secrets/logs/working files).
# .gitignore covers: *.ipa, *.dSYM.zip, *.log, fastlane/report.xml, build/, DerivedData*/
echo "Staging code changes (excluding secrets/logs)..."
git add -A -- ':!*.ipa' ':!*.dSYM.zip' ':!*.log' ':!fastlane/report.xml' ':!DerivedData' ':!build' || true
if git diff --cached --quiet; then
  echo "Nothing to commit."
else
  MARKETING_VERSION="$(xcodebuild -showBuildSettings -project Dientempo.xcodeproj -scheme Dientempo -configuration Release 2>/dev/null | sed -n 's/.*MARKETING_VERSION = //p' | head -1)"
  git commit -m "chore: TestFlight build ${MARKETING_VERSION:-?} (${NEXT_BUILD}) — expire old, push after upload" || echo "Commit failed" >&2
  git push || echo "Push failed — push manually" >&2
fi

echo "Done — check https://appstoreconnect.apple.com/teams/69a6de90-d3c4-47e3-e053-5b8c7c11a4d1/apps/6780648670/testflight"
