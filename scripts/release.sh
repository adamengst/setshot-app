#!/bin/bash
#
# Builds, notarises and publishes a SetShot release.
#
#   scripts/release.sh              # build and publish
#   scripts/release.sh --dry-run    # everything local, stop before publishing
#
# The version comes from project.yml, so bump MARKETING_VERSION and
# CURRENT_PROJECT_VERSION and commit before running this.
#
# Everything up to the confirmation prompt is local or, in the case of
# notarisation, an upload to Apple that publishes nothing. Creating the GitHub
# release and pushing the appcast are what make a release visible to users, and
# both happen after the prompt.
#
# Signing keys stay in the keychain. Nothing here needs them anywhere else, which
# is why this is a script you run rather than a CI job.

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

TEAM_ID="6SCP2R96HY"
NOTARY_PROFILE="SetShot-notarize"
GITHUB_REPO="adamengst/setshot-app"

step()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
info()  { printf '    %s\n' "$1"; }
fail()  { printf '\n\033[31mError: %s\033[0m\n' "$1" >&2; exit 1; }

# ── Version ───────────────────────────────────────────────────────────────────

VERSION="$(grep 'MARKETING_VERSION:' project.yml | head -1 | sed 's/.*: *"\(.*\)"/\1/')"
BUILD="$(grep 'CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed 's/.*: *"\(.*\)"/\1/')"
[ -n "$VERSION" ] || fail "Could not read MARKETING_VERSION from project.yml"
[ -n "$BUILD" ]   || fail "Could not read CURRENT_PROJECT_VERSION from project.yml"

TAG="v$VERSION"
WORK="/tmp/setshot-release-$VERSION"
ZIP="$WORK/SetShot-$VERSION.zip"
DMG="$WORK/SetShot-$VERSION.dmg"

step "SetShot $VERSION (build $BUILD)"
$DRY_RUN && info "dry run: will stop before publishing"

# ── Preflight ─────────────────────────────────────────────────────────────────

step "Checking the working tree"

[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || fail "Not on main"
[ -z "$(git status --porcelain | grep -v '^??')" ] || fail "Uncommitted changes — commit them first"

git fetch origin --quiet
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
  || fail "main and origin/main differ — push or pull first"
info "on main, clean, in step with origin"

# A tag or appcast entry that already exists means this version went out already.
git rev-parse "$TAG" >/dev/null 2>&1 && fail "Tag $TAG already exists — bump the version in project.yml"
grep -q "<sparkle:shortVersionString>$VERSION<" appcast.xml \
  && fail "appcast.xml already has an entry for $VERSION"
grep -q "<sparkle:version>$BUILD<" appcast.xml \
  && fail "appcast.xml already has build $BUILD — Sparkle compares on this, so it has to increase"
info "version $VERSION and build $BUILD are unpublished"

security find-identity -v -p codesigning | grep -q "Developer ID Application" \
  || fail "No Developer ID Application identity in the keychain"
# `history` is the cheapest call that proves the stored credentials still work.
# There is no local way to check: notarytool does not put the profile anywhere
# `security` can find it. Worth the round trip, since the alternative is finding out
# after a ten-minute archive.
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null 2>&1 \
  || fail "Notarisation profile '$NOTARY_PROFILE' does not work (xcrun notarytool store-credentials)"
command -v gh >/dev/null || fail "gh is not installed"
gh auth status >/dev/null 2>&1 || fail "gh is not authenticated"
info "signing identity, notary profile and gh all present"

step "Checking for pending knowledge base submissions"
PENDING="$(gh issue list --repo adamengst/setshot-submissions --label pending --json number -q 'length' 2>/dev/null || echo "?")"
if [ "$PENDING" != "0" ] && [ "$PENDING" != "?" ]; then
    info "$PENDING open submission(s) labelled 'pending' — process them first if they belong in this release"
    read -r -p "    Continue anyway? [y/N] " reply
    [ "$reply" = "y" ] || exit 1
else
    info "none pending"
fi

# ── Build ─────────────────────────────────────────────────────────────────────

step "Running the tests"
xcodegen generate >/dev/null
xcodebuild test -project SetShot.xcodeproj -scheme SetShot \
    -destination 'platform=macOS' -quiet \
  || fail "Tests failed"
info "all tests passed"

step "Archiving"
rm -rf "$WORK"; mkdir -p "$WORK"
xcodebuild archive -project SetShot.xcodeproj -scheme SetShot \
    -destination 'generic/platform=macOS' -archivePath "$WORK/SetShot.xcarchive" -quiet \
  || fail "Archive failed"

xcodebuild -exportArchive -archivePath "$WORK/SetShot.xcarchive" \
    -exportPath "$WORK/export" -exportOptionsPlist ExportOptions.plist -quiet \
  || fail "Export failed"
APP="$WORK/export/SetShot.app"
[ -d "$APP" ] || fail "No app at $APP"
info "exported $(du -sh "$APP" | cut -f1) app"

# ── Notarise the app ──────────────────────────────────────────────────────────
#
# -exportArchive does not reliably notarise, so it is always submitted by hand.

step "Notarising the app (this takes a few minutes)"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/notarize-app.zip"
xcrun notarytool submit "$WORK/notarize-app.zip" \
    --keychain-profile "$NOTARY_PROFILE" --wait \
  || fail "Notarisation failed"
xcrun stapler staple "$APP" || fail "Stapling the app failed"
xcrun stapler validate "$APP" >/dev/null || fail "Staple did not validate"
info "app notarised and stapled"

# ── Zip, for Sparkle ──────────────────────────────────────────────────────────
#
# ditto rather than zip, so the signature and the executable's link date survive —
# the About panel reports that date to tell one build from another.

step "Building the zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
ZIP_SIZE="$(stat -f %z "$ZIP")"
info "$(basename "$ZIP") — $ZIP_SIZE bytes"

# ── Disk image, for people downloading by hand ────────────────────────────────
#
# An app opened from where it was unzipped is translocated by Gatekeeper: macOS
# runs it from a randomised copy, where scheduled snapshots cannot work and updates
# cannot install. Dragging it out is what avoids that, so the image holds an
# Applications symlink to make that the obvious gesture. SetShot warns when it
# finds itself translocated, but not landing there is better.

step "Building the disk image"
STAGE="$WORK/dmg-staging"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/SetShot.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "SetShot $VERSION" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG" -quiet \
  || fail "Building the disk image failed"

codesign --sign "Developer ID Application" --timestamp "$DMG" \
  || fail "Signing the disk image failed"

step "Notarising the disk image (this takes a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait \
  || fail "Notarising the disk image failed"
xcrun stapler staple "$DMG" || fail "Stapling the disk image failed"
xcrun stapler validate "$DMG" >/dev/null || fail "Disk image staple did not validate"
info "$(basename "$DMG") — $(du -sh "$DMG" | cut -f1), notarised and stapled"

# ── Sparkle signature ─────────────────────────────────────────────────────────

step "Signing the zip for Sparkle"
SIGN_UPDATE="$(ls -t ~/Library/Developer/Xcode/DerivedData/SetShot-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update 2>/dev/null | head -1)"
[ -x "${SIGN_UPDATE:-}" ] || fail "sign_update not found — build once so SPM fetches Sparkle"
SIGN_OUTPUT="$("$SIGN_UPDATE" "$ZIP")"
ED_SIGNATURE="$(printf '%s' "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
[ -n "$ED_SIGNATURE" ] || fail "Could not read the signature from: $SIGN_OUTPUT"
info "signed"

# ── Publish ───────────────────────────────────────────────────────────────────

step "Ready to publish"
info "version:   $VERSION (build $BUILD)"
info "zip:       $ZIP ($ZIP_SIZE bytes)"
info "disk image: $DMG"
info "tag:       $TAG on $GITHUB_REPO"
echo

if $DRY_RUN; then
    step "Dry run — stopping here"
    info "the artefacts above are built, notarised and stapled; nothing was published"
    exit 0
fi

read -r -p "Publish this release? [y/N] " reply
[ "$reply" = "y" ] || { info "Nothing published. Artefacts are in $WORK"; exit 1; }

step "Creating the GitHub release"
gh release create "$TAG" "$ZIP" "$DMG" \
    --title "SetShot $VERSION" \
    --notes "See the release notes in the app, or ReleaseNotes.md." \
    --repo "$GITHUB_REPO" \
  || fail "Creating the release failed"

step "Updating appcast.xml"
PUB_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
URL="https://github.com/$GITHUB_REPO/releases/download/$TAG/SetShot-$VERSION.zip"

VERSION="$VERSION" BUILD="$BUILD" PUB_DATE="$PUB_DATE" URL="$URL" \
ED_SIGNATURE="$ED_SIGNATURE" ZIP_SIZE="$ZIP_SIZE" python3 - <<'PY'
import os
version, build = os.environ["VERSION"], os.environ["BUILD"]
item = f"""        <item>
            <title>SetShot {version}</title>
            <pubDate>{os.environ["PUB_DATE"]}</pubDate>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure
                url="{os.environ["URL"]}"
                sparkle:edSignature="{os.environ["ED_SIGNATURE"]}"
                length="{os.environ["ZIP_SIZE"]}"
                type="application/octet-stream"
            />
        </item>
"""
path = "appcast.xml"
text = open(path).read()
# Newest first, so the new item goes immediately before the current top one.
marker = "        <item>"
index = text.index(marker)
open(path, "w").write(text[:index] + item + text[index:])
print(f"    added {version} (build {build}) to appcast.xml")
PY

xmllint --noout appcast.xml 2>/dev/null || fail "appcast.xml is not valid XML — fix it before pushing"

step "Committing and pushing the appcast"
git add appcast.xml
git commit -q -m "Release $VERSION"
git push origin main

step "Released"
info "SetShot $VERSION is published and the appcast points at it"
info "artefacts: $WORK"
