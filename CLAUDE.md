# SetShot — Claude Procedures

## Reviewing KB Submissions

New submissions arrive as GitHub Issues in `adamengst/setshot-kb` with the label `pending`. Run through these steps in order:

1. List open submissions:
   ```
   gh issue list --repo adamengst/setshot-kb --label pending
   ```

2. View each issue and decide: **noise** (suppress silently), **KB entry** (add with description/location), or **needs more info**.

3. Edit `settings-kb.json` in `/Users/adam/Documents/GitHub/setshot-kb/`:
   - Noise entry: `"noise": true`, `"noise_reason": "..."`, leave `description`/`ui_location`/`settings_url` null.
   - If the key contains array indices (`[0]`) or UUIDs, use `"key": ""` and `"key_prefix": "..."` instead of an exact key.
   - Known entry: fill `description`, `ui_location`, `settings_url` (x-apple.systempreferences: URL if applicable), `value_map` if the values need human labels.
   - Set `"contributed_by_issue": <issue number>` in all cases.

4. Bump `version.json` — increment `version` by 1, update `updated_at` to current UTC timestamp.

5. Commit and push in `setshot-kb`:
   ```
   git add settings-kb.json version.json
   git commit -m "Description of changes (issues #N, #M)"
   git push
   ```

6. Close each issue with a comment explaining what was done and which KB version it landed in.

---

## Releasing a New Version

### Before archiving

1. Check for pending KB submissions and process them first:
   ```
   gh issue list --repo adamengst/setshot-kb --label pending
   ```

2. Increment `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` (e.g. `1.0` → `1.1`, build `1` → `2`).
3. Run `xcodegen generate` to update the `.xcodeproj`.
4. Run the test suite and confirm all tests pass:
   ```
   xcodebuild test -project SetShot.xcodeproj -scheme SetShot -destination 'platform=macOS'
   ```
5. Commit `project.yml` (and any other pending changes) and push.

### Building, notarizing, and stapling

4. Archive and export — all output goes to `/tmp/`:
   ```
   xcodebuild archive \
     -project SetShot.xcodeproj \
     -scheme SetShot \
     -destination 'generic/platform=macOS' \
     -archivePath /tmp/SetShot.xcarchive

   xcodebuild -exportArchive \
     -archivePath /tmp/SetShot.xcarchive \
     -exportPath /tmp/SetShot-export \
     -exportOptionsPlist ExportOptions.plist
   ```

5. Notarize and staple:
   ```
   ditto -c -k --sequesterRsrc --keepParent /tmp/SetShot-export/SetShot.app /tmp/SetShot-notarize.zip
   xcrun notarytool submit /tmp/SetShot-notarize.zip --keychain-profile SetShot-notarize --wait
   xcrun stapler staple /tmp/SetShot-export/SetShot.app
   ```
   (`xcodebuild -exportArchive` does not reliably auto-notarize, so submit manually every time.)

6. Zip the stapled app:
   ```
   ditto -c -k --sequesterRsrc --keepParent /tmp/SetShot-export/SetShot.app /tmp/SetShot-X.Y.zip
   ```

### Signing for Sparkle

7. Generate the EdDSA signature:
   ```
   ~/Library/Developer/Xcode/DerivedData/SetShot-dudffzkhimmftwbvygszwmzrzgpd/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update /tmp/SetShot-X.Y.zip
   ```
   Note the `sparkle:edSignature` and `length` values.

### Publishing

8. Create the GitHub Release and upload the zip:
   ```
   gh release create vX.Y /tmp/SetShot-X.Y.zip \
     --title "SetShot X.Y" \
     --notes "..." \
     --repo adamengst/setshot-app
   ```

9. Add a new `<item>` to `appcast.xml` in `setshot-app`:
    - `<sparkle:version>` = build number (integer)
    - `<sparkle:shortVersionString>` = marketing version (e.g. `1.1`)
    - `url` = `https://github.com/adamengst/setshot-app/releases/download/vX.Y/SetShot-X.Y.zip`
    - `sparkle:edSignature` and `length` from step 7
    - `pubDate` in RFC-2822 format

10. Commit and push `appcast.xml` (and `project.yml` if not already pushed):
    ```
    git add appcast.xml project.yml
    git commit -m "Release X.Y"
    git push
    ```

### Deploying the Cloudflare worker

After changes to `worker.js`, deploy with:
```
wrangler deploy
```
(Run from the `setshot-app` repo directory. Requires `wrangler` installed via `npm install -g wrangler` and authenticated via `wrangler login`.)

### Signing details
- Team ID: `6SCP2R96HY` (TidBITS Publishing Inc.)
- Notarization keychain profile: `SetShot-notarize`
- Code signing identity: `Developer ID Application`
- Sparkle public key (SUPublicEDKey): `7TX+CFEbqGbKIprRyq2sdjgmf7l3BrJf/bzp/Ss0ndg=`
