#!/bin/bash
# Builds the styled disk image: app on the left, arrow, Applications on the right.
#
#   dmg/build-dmg.sh <app path> <output dmg> <volume name>
#
# The layout is set through Finder, which only works on a writable image, so this
# builds read-write, dresses the window, then converts to the compressed read-only
# image that ships. The window bounds match dmg/background.tiff exactly -- change one
# and the other needs changing too, or scroll bars appear.
set -euo pipefail

APP="$1"; OUT="$2"; VOLNAME="$3"
HERE="$(cd "$(dirname "$0")" && pwd)"
BACKGROUND="$HERE/background.tiff"
[ -f "$BACKGROUND" ] || { echo "No background at $BACKGROUND (run: swift $HERE/make-background.swift)"; exit 1; }

# WIDTH/HEIGHT are the background image's size, which is the content area we want.
# Finder's `bounds` is the whole window frame, title bar included, so the bar's height
# is added on -- set bounds to the background's height and the content comes up short,
# which is what puts a scroll bar in the window.
WIDTH=640; HEIGHT=400; ICON_SIZE=128; TITLEBAR=28
APP_X=160; APP_Y=180; APPS_X=480; APPS_Y=180

WORK="$(mktemp -d)"
MOUNT=""
# Detaching has to come before the temp directory goes, or the volume stays attached
# and the removal fails half-done.
cleanup() {
  [ -n "$MOUNT" ] && hdiutil detach "$MOUNT" -force -quiet 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT
STAGE="$WORK/stage"; mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"
cp "$BACKGROUND" "$STAGE/.background/background.tiff"

RW="$WORK/rw.dmg"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDRW -quiet "$RW"

# Mounted where Finder can see it: the layout is set by telling Finder about
# `disk "<volume name>"`, and -nobrowse hides the volume from Finder entirely, so the
# script cannot then address what it just mounted. -noautoopen keeps a window from
# springing up in the face of whoever is running this.
#
# The mount point is read back rather than assumed to be /Volumes/<volume name>. If a
# volume of that name is already mounted -- a previous run that did not clean up, or a
# disk image someone left open -- macOS mounts this one as "<name> 1" instead. Assuming
# the plain path then pointed Finder at a volume that was not there and left the real
# one mounted afterwards, because the cleanup detached the path that never existed.
MOUNT="$(hdiutil attach "$RW" -noverify -noautoopen -plist \
  | plutil -extract system-entities json -o - - \
  | python3 -c 'import json,sys; print(next(e["mount-point"] for e in json.load(sys.stdin) if e.get("mount-point")))')"
[ -d "$MOUNT" ] || { echo "Could not determine where the image mounted"; exit 1; }
# Finder is told the name it actually got, which is what makes a collision harmless.
FINDER_VOL="$(basename "$MOUNT")"
[ "$FINDER_VOL" = "$VOLNAME" ] || echo "    note: mounted as \"$FINDER_VOL\" (a volume named \"$VOLNAME\" was already mounted)"

osascript - "$FINDER_VOL" "$WIDTH" "$((HEIGHT + TITLEBAR))" "$ICON_SIZE" \
             "$APP_X" "$APP_Y" "$APPS_X" "$APPS_Y" "$(basename "$APP")" <<'APPLESCRIPT'
on run argv
  set {vol, w, h, iconSize, ax, ay, px, py, appName} to argv
  tell application "Finder"
    tell disk vol
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set the bounds of container window to {200, 120, 200 + (w as integer), 120 + (h as integer)}
      set opts to the icon view options of container window
      set arrangement of opts to not arranged
      set icon size of opts to (iconSize as integer)
      set text size of opts to 12
      set background picture of opts to file ".background:background.tiff"
      set position of item appName of container window to {ax as integer, ay as integer}
      set position of item "Applications" of container window to {px as integer, py as integer}
      update without registering applications
      -- Setting these once before the layout is written does not always stick, so they
      -- are set again on a reopened window, which is what lands in the .DS_Store that
      -- ships. Note the path bar is not covered: Finder has no scripting term for it and
      -- it is a global preference, off by default, so someone who turns it on sees it
      -- here as they do everywhere.
      close
      open
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set the bounds of container window to {200, 120, 200 + (w as integer), 120 + (h as integer)}
      update without registering applications
      close
    end tell
  end tell
end run
APPLESCRIPT

# Finder writes .DS_Store lazily; without settling, the layout can be lost.
sync
hdiutil detach "$MOUNT" -quiet
MOUNT=""

rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" -quiet
echo "built $OUT"
