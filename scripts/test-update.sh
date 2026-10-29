#!/bin/bash
#
# Tests a release candidate's update path before it is published: an older,
# published SetShot updates itself to the candidate from a feed served on this Mac.
#
#   scripts/release.sh --dry-run        # builds, notarises and staples the zip
#   scripts/test-update.sh              # updates the latest published release to it
#   scripts/test-update.sh --from v1.0b31
#   scripts/test-update.sh path/to/SetShot-X.Y.zip
#
# Sparkle prefers a SUFeedURL in the app's user defaults to the one in Info.plist,
# which is what makes this possible without a special build. The script sets it,
# serves a one-item appcast on localhost, launches the old copy from
# ~/Applications/SetShot-update-test, removes the override once SetShot has fetched
# the feed, and waits for the copy to come back as the new build. The update runs
# as it will for users: download, EdDSA and length check, install, relaunch.
#
# Nothing is published. The zip is signed with the Sparkle key in the keychain, as
# release.sh does, and the old release is downloaded from GitHub with gh.

set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_ID="com.tidbits.SetShot"
GITHUB_REPO="adamengst/setshot-app"
PORT=8765
# Not ~/Desktop: with iCloud Drive syncing Desktop & Documents, macOS refuses the
# rename Sparkle swaps the app in with (EDEADLK, "Resource deadlock avoided").
TEST_DIR="$HOME/Applications/SetShot-update-test"
WORK="$(mktemp -d /tmp/setshot-update-test.XXXXXX)"

step()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
info()  { printf '    %s\n' "$1"; }
fail()  { printf '\n\033[31mError: %s\033[0m\n' "$1" >&2; exit 1; }

FROM_TAG=""
ZIP=""
while [ $# -gt 0 ]; do
    case "$1" in
        --from) FROM_TAG="${2:-}"; [ -n "$FROM_TAG" ] || fail "--from needs a tag"; shift 2 ;;
        -*)     fail "Unknown option $1" ;;
        *)      ZIP="$1"; shift ;;
    esac
done

# ── Candidate ─────────────────────────────────────────────────────────────────

if [ -z "$ZIP" ]; then
    VERSION="$(grep 'MARKETING_VERSION:' project.yml | head -1 | sed 's/.*: *"\(.*\)"/\1/')"
    ZIP="/tmp/setshot-release-$VERSION/SetShot-$VERSION.zip"
fi
[ -f "$ZIP" ] || fail "No zip at $ZIP — run scripts/release.sh --dry-run first, or pass a zip"

# Read the version from the app inside the zip rather than project.yml, so the feed
# describes what is in the zip.
unzip -p "$ZIP" SetShot.app/Contents/Info.plist > "$WORK/candidate.plist" \
  || fail "$ZIP does not contain SetShot.app"
NEW_VERSION="$(plutil -extract CFBundleShortVersionString raw "$WORK/candidate.plist")"
NEW_BUILD="$(plutil -extract CFBundleVersion raw "$WORK/candidate.plist")"

step "Candidate: SetShot $NEW_VERSION (build $NEW_BUILD)"
info "$ZIP"

# ── Old release ───────────────────────────────────────────────────────────────

if [ -z "$FROM_TAG" ]; then
    FROM_TAG="$(gh release list --repo "$GITHUB_REPO" --exclude-drafts --limit 1 \
                  --json tagName --jq '.[0].tagName')"
    [ -n "$FROM_TAG" ] || fail "Could not find a published release"
    [ "$FROM_TAG" != "v$NEW_VERSION" ] \
      || fail "$FROM_TAG is already published; pick an older one with --from"
fi

step "Installing $FROM_TAG in $TEST_DIR"
mkdir -p "$WORK/old"
gh release download "$FROM_TAG" --repo "$GITHUB_REPO" --pattern '*.zip' --dir "$WORK/old" \
  || fail "Could not download a zip from release $FROM_TAG"
OLD_ZIP="$(ls "$WORK"/old/*.zip | head -1)"

rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
ditto -x -k "$OLD_ZIP" "$TEST_DIR"
OLD_APP="$TEST_DIR/SetShot.app"
[ -d "$OLD_APP" ] || fail "$(basename "$OLD_ZIP") does not contain SetShot.app"

OLD_BUILD="$(plutil -extract CFBundleVersion raw "$OLD_APP/Contents/Info.plist")"
OLD_VERSION="$(plutil -extract CFBundleShortVersionString raw "$OLD_APP/Contents/Info.plist")"
info "SetShot $OLD_VERSION (build $OLD_BUILD)"
[ "$OLD_BUILD" -lt "$NEW_BUILD" ] \
  || fail "Build $OLD_BUILD is not older than $NEW_BUILD, so Sparkle would offer nothing"

# ── Feed ──────────────────────────────────────────────────────────────────────

step "Signing the candidate and writing the feed"
SIGN_UPDATE="$(ls -t ~/Library/Developer/Xcode/DerivedData/SetShot-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update 2>/dev/null | head -1)"
[ -x "${SIGN_UPDATE:-}" ] || fail "sign_update not found — build once so SPM fetches Sparkle"
SIGN_OUTPUT="$("$SIGN_UPDATE" "$ZIP")"
ED_SIGNATURE="$(printf '%s' "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
[ -n "$ED_SIGNATURE" ] || fail "Could not read the signature from: $SIGN_OUTPUT"
ZIP_SIZE="$(stat -f%z "$ZIP")"

FEED="$WORK/feed"
mkdir -p "$FEED"
cp "$ZIP" "$FEED/SetShot-$NEW_VERSION.zip"
cat > "$FEED/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>SetShot local update test</title>
        <item>
            <title>SetShot $NEW_VERSION</title>
            <pubDate>$(date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
            <sparkle:version>$NEW_BUILD</sparkle:version>
            <sparkle:shortVersionString>$NEW_VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <description><![CDATA[<p>Local update test from scripts/test-update.sh.</p>]]></description>
            <enclosure
                url="http://localhost:$PORT/SetShot-$NEW_VERSION.zip"
                sparkle:edSignature="$ED_SIGNATURE"
                length="$ZIP_SIZE"
                type="application/octet-stream"
            />
        </item>
    </channel>
</rss>
XML
info "http://localhost:$PORT/appcast.xml"

# ── Serve and launch ──────────────────────────────────────────────────────────

lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 && fail "Port $PORT is already in use"

SERVER_PID=""
cleanup() {
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
    defaults delete "$BUNDLE_ID" SUFeedURL 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT
# Turn Ctrl-C or a closed Terminal window into an ordinary exit, so the override
# never outlives the test.
trap 'exit 1' INT TERM HUP

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$FEED" > "$WORK/server.log" 2>&1 &
SERVER_PID=$!
sleep 1
kill -0 "$SERVER_PID" 2>/dev/null || fail "The feed server did not start: $(cat "$WORK/server.log")"

# Only one SetShot can run, and the copy in /Applications shares these defaults.
killall SetShot 2>/dev/null || true
defaults write "$BUNDLE_ID" SUFeedURL "http://localhost:$PORT/appcast.xml"

step "Launching $OLD_VERSION"
open "$OLD_APP"
info "Choose Check for Updates if SetShot doesn't offer $NEW_VERSION at launch (it"
info "won't when automatic checks are off). Install the update and let it relaunch."
info "Ctrl-C gives up."

# Once SetShot has the feed, the download URL comes from the feed itself, so the
# override can go. Removing it here rather than only at exit means a killed run
# can't leave the copy in /Applications pointed at a server that is gone.
until grep -q '"GET /appcast.xml' "$WORK/server.log"; do sleep 1; done
defaults delete "$BUNDLE_ID" SUFeedURL 2>/dev/null || true
info "feed fetched; the SUFeedURL override is removed"

# The update has worked when the copy holds the new build and is running again.
installed_build() { plutil -extract CFBundleVersion raw "$OLD_APP/Contents/Info.plist" 2>/dev/null || true; }
DEADLINE=$((SECONDS + 600))
until [ "$(installed_build)" = "$NEW_BUILD" ] && pgrep -f "$OLD_APP/Contents/MacOS/SetShot" >/dev/null; do
    [ $SECONDS -lt $DEADLINE ] || break
    sleep 2
done

# ── Result ────────────────────────────────────────────────────────────────────

step "Result"
grep -E '"GET ' "$WORK/server.log" | sed 's/^.*"GET \([^ ]*\) [^"]*" \([0-9]*\).*/    GET \1 → \2/'
echo

INSTALLED_VERSION="$(plutil -extract CFBundleShortVersionString raw "$OLD_APP/Contents/Info.plist")"
if [ "$(installed_build)" = "$NEW_BUILD" ]; then
    info "Passed: $TEST_DIR holds $INSTALLED_VERSION (build $NEW_BUILD) and it relaunched"
    info "Quit the test copy and delete $TEST_DIR when done."
else
    info "Failed: $TEST_DIR holds $INSTALLED_VERSION (build $(installed_build)) after ten minutes"
    info "Sparkle's log: /usr/bin/log show --last 15m --style compact --predicate 'process == \"Autoupdate\"'"
    exit 1
fi
