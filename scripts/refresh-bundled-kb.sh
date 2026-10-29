#!/bin/bash
#
# Copies the knowledge base from a setshot-kb checkout into the app, so SetShot
# has a KB on a first launch with no network or with raw.githubusercontent.com
# blocked. The copies are checked in; commit them after running this.
#
#   scripts/refresh-bundled-kb.sh                 # from ~/GitHub/setshot-kb
#   SETSHOT_KB_REPO=/path/to/setshot-kb scripts/refresh-bundled-kb.sh
#
# This is a script rather than a build phase because ENABLE_USER_SCRIPT_SANDBOXING
# is on, and a build-phase script that reads outside the repo fails.

set -euo pipefail

cd "$(dirname "$0")/.."

KB_REPO="${SETSHOT_KB_REPO:-$HOME/GitHub/setshot-kb}"
DEST="SetShot/Resources/BundledKB"

for f in settings-kb.json version.json; do
    [ -f "$KB_REPO/$f" ] || { echo "Error: no $f in $KB_REPO" >&2; exit 1; }
    python3 -I -m json.tool "$KB_REPO/$f" >/dev/null || { echo "Error: $KB_REPO/$f is not valid JSON" >&2; exit 1; }
done

mkdir -p "$DEST"
cp "$KB_REPO/settings-kb.json" "$KB_REPO/version.json" "$DEST/"

echo "Bundled KB is now version $(plutil -extract version raw -o - "$DEST/version.json")"
