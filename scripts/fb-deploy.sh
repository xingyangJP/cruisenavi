#!/usr/bin/env bash
#
# The ONLY sanctioned way to deploy Firebase from this repo.
# It (1) runs the accident guard, then (2) forces --project ridelane so the
# global active project can never redirect a deploy to the wrong project.
#
# Usage:
#   scripts/fb-deploy.sh --only firestore:rules
#   scripts/fb-deploy.sh --only firestore
#   scripts/fb-deploy.sh            # whatever firebase.json defines
#
# Never run a bare `firebase deploy` in this repo — use this wrapper.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/firebase-guard.sh"

echo "→ firebase deploy --project ridelane $*"
exec firebase deploy --project ridelane "$@"
