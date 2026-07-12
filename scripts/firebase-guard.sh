#!/usr/bin/env bash
#
# Firebase accident guard for the RideLane repo.
# Fails fast if anything in this working copy points at a Firebase project
# other than `ridelane`. Prevents cross-project mistakes when several
# Firebase projects are developed in parallel on the same machine.
#
# Run manually any time:   scripts/firebase-guard.sh
# It is also invoked by scripts/fb-deploy.sh before every deploy.
set -euo pipefail

EXPECTED="ridelane"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "❌ Firebase guard FAILED: $1" >&2; exit 1; }

# 1) The app config bundled into the build must target the expected project.
PLIST="$ROOT/GoogleService-Info.plist"
[ -f "$PLIST" ] || fail "GoogleService-Info.plist not found at repo root."
PID="$(/usr/libexec/PlistBuddy -c 'Print :PROJECT_ID' "$PLIST" 2>/dev/null || true)"
[ "$PID" = "$EXPECTED" ] || fail "GoogleService-Info.plist PROJECT_ID='$PID' (expected '$EXPECTED'). Wrong Firebase config committed for this repo."

# 2) The repo's Firebase default project must be the expected project.
RC="$ROOT/.firebaserc"
[ -f "$RC" ] || fail ".firebaserc missing — CLI would fall back to the global active project."
RC_DEFAULT="$(python3 -c "import json;print(json.load(open('$RC'))['projects'].get('default',''))" 2>/dev/null || true)"
[ "$RC_DEFAULT" = "$EXPECTED" ] || fail ".firebaserc default='$RC_DEFAULT' (expected '$EXPECTED')."

# 3) The CLI's ACTUAL resolved project for this directory must match.
#    (.firebaserc default can be silently overridden by the global active-project
#    store — this is the real cross-project accident vector, so check it directly.)
ACTIVE="$(cd "$ROOT" && firebase use 2>/dev/null | tr -d '[:space:]' || true)"
if [ "$ACTIVE" != "$EXPECTED" ]; then
  fail "firebase CLI active project is '$ACTIVE' (expected '$EXPECTED'). Run: firebase use $EXPECTED"
fi

echo "✅ Firebase guard OK — project '$EXPECTED' (plist + .firebaserc + active CLI target verified)."
