# SetShot — Complete Project Specification

## Overview

SetShot is a macOS utility that snapshots system settings before and after a macOS update (or any system change), diffs the two snapshots, and presents the changes in human-readable form. It maintains a community-grown knowledge base (KB) of known settings, fetched live from GitHub. When it encounters a change it doesn't recognise, it lets the user submit it for curation. A Cowork session periodically processes submissions in batch and commits interpreted entries back to the KB.

---

## Components

| Component | What it is | Where it lives |
|---|---|---|
| SetShot.app | SwiftUI macOS app | `setshot-app` GitHub repo |
| Knowledge base | JSON file + version file | `setshot-kb` GitHub repo (public) |
| Cloudflare Worker | Submission endpoint | Cloudflare dashboard |
| GitHub Actions workflow | Converts approved issues to PRs | `setshot-kb` repo |
| Cowork curation session | Batch-processes pending submissions | Claude app (Cowork) |
| Claude Project | Holds curation context and prompt | Claude app (Projects) |

---

## Manual Setup Steps

These are the things only you can do. Complete them in order before any development begins.

### 1. GitHub account and 2FA

If you don't already have a GitHub account, create one at https://github.com. Once logged in, immediately enable two-factor authentication: Settings → Password and security → Two-factor authentication. Use an authenticator app rather than SMS.

### 2. GitHub Desktop

Download and install GitHub Desktop from https://desktop.github.com. Sign in with your GitHub account during setup.

### 3. Xcode

Install Xcode from the Mac App Store. It is large (~10 GB); plan around the download time. Once installed, open it once and accept the license agreement and component installation prompts before doing anything else.

### 4. Create the two GitHub repositories

In GitHub Desktop: File → New Repository.

**Repository 1 — the KB:**
- Name: `setshot-kb`
- Description: `Knowledge base for the SetShot macOS settings diff tool`
- Make it **Public**
- Initialize with a README: yes
- Git ignore: None
- License: MIT

**Repository 2 — the app:**
- Name: `setshot-app`
- Description: `SetShot macOS app — snapshot and diff macOS settings changes`
- Make it **Public** (or Private if you prefer; Public allows community contributions)
- Initialize with a README: yes
- Git ignore: Swift
- License: MIT

GitHub Desktop will clone both repos to your Mac automatically.

### 5. Seed the KB repository

In the `setshot-kb` folder on your Mac, create the following files. GitHub Desktop will show them as uncommitted changes; commit and push after creating all three.

**`version.json`**
```json
{
  "version": 1,
  "updated_at": "2026-01-01T00:00:00Z"
}
```

**`settings-kb.json`**
```json
[]
```

**`prompts/interpret-diff.md`** — see the Curation Prompt section below for full contents.

### 6. Create a GitHub Personal Access Token for the Worker

Go to GitHub.com → Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token.

Settings:
- Token name: `setshot-worker`
- Expiration: No expiration (or 1 year and calendar a renewal reminder)
- Resource owner: your account
- Repository access: Only select repositories → `setshot-kb`
- Permissions → Repository permissions:
  - Issues: Read and write
  - Everything else: No access

Copy the token immediately — GitHub will not show it again. Store it somewhere safe (a password manager).

### 7. Create a GitHub Personal Access Token for Cowork

Repeat the above with these differences:
- Token name: `setshot-cowork`
- Permissions → Repository permissions:
  - Issues: Read and write
  - Contents: Read and write
  - Pull requests: Read and write

This token needs broader access because Cowork will read issues, write KB files, and create PRs.

Store this token in your password manager too.

### 8. Create the Cloudflare Worker

Go to https://cloudflare.com and create a free account if you don't have one. Free tier is sufficient indefinitely for this use case.

Once logged in:
1. In the left sidebar, click **Workers & Pages**.
2. Click **Create** → **Create Worker**.
3. Name it `setshot-submission`.
4. Click **Deploy** (deploys the placeholder; you'll replace the code later).
5. On the worker's page, go to **Settings** → **Variables and Secrets**.
6. Add a secret (not a variable): name `GITHUB_TOKEN`, value = the `setshot-worker` token from step 6.
7. Add a variable: name `GITHUB_REPO`, value = `your-github-username/setshot-kb`.

Note the Worker URL shown on the worker's page — it will look like `https://setshot-submission.your-subdomain.workers.dev`. You'll need this when building the app.

The Worker code itself will be written by a Code session. What you've done here is create the deployment target and securely store the credentials it needs.

### 9. Create the Claude Project for KB curation

In the Claude app, create a new Project named `SetShot KB Curation`.

In the Project instructions, paste:

```
You are helping curate the SetShot knowledge base. SetShot is a macOS utility 
that diffs system settings snapshots and presents changes in human-readable form.

The KB is a JSON array of entries. Each entry describes one macOS setting that 
SetShot can detect. When given raw diff lines from SetShot output, your job is 
to interpret each one and produce a valid KB entry.

The KB schema is:
{
  "id": "domain-fragment.KeyName",         // stable slug, no spaces
  "domain": "com.apple.example",           // defaults domain or full plist path
  "key": "KeyName",                        // the key name from the diff line
  "source": "defaults",                    // defaults | plist | tcc | pmset | scutil | networksetup | systemsetup
  "value_type": "bool",                    // bool | int | float | string | date | data
  "description": "...",                    // plain English: what does this setting do?
  "ui_location": "...",                    // breadcrumb path in System Settings, or app name if app-specific, or null
  "settings_url": "...",                   // x-apple.systempreferences: URL or null
  "noise": false,                          // true if this key changes constantly without user action
  "noise_reason": null,                    // if noise: why (e.g. "Timestamp updated on every sync")
  "min_macos": "13.0",                     // earliest macOS version where this key is known to exist
  "notes": null,                           // optional: edge cases, enum values, caveats
  "ai_generated": true,                    // always true for entries you produce
  "contributed_by_issue": null             // leave null; the workflow fills this in
}

Rules:
- If you are not confident about ui_location, set it to null rather than guessing.
- If no System Settings pane exists for this key (e.g. it is app-specific), set settings_url to null.
- settings_url must begin with exactly "x-apple.systempreferences:" — no other schemes.
- For noise entries, set noise: true and explain why in noise_reason.
- Produce only valid JSON. No commentary outside the JSON.
- If given multiple diff lines, produce a JSON array of entries.
```

### 10. GitHub Actions workflow

In the `setshot-kb` repo on your Mac, create the file `.github/workflows/process-approved.yml` with the contents provided in the GitHub Actions Workflow section below. Commit and push.

Then create a GitHub Actions secret in the repo:
- Go to the `setshot-kb` repo on github.com → Settings → Secrets and variables → Actions → New repository secret.
- Name: `KB_WRITER_TOKEN`
- Value: the `setshot-cowork` token from step 7.

---

## Repository Structure

### `setshot-kb`

```
setshot-kb/
├── version.json
├── settings-kb.json
├── prompts/
│   └── interpret-diff.md        ← curation prompt (same as Project instructions above)
└── .github/
    └── workflows/
        └── process-approved.yml
```

### `setshot-app`

```
setshot-app/
├── SetShot/
│   ├── SetShotApp.swift
│   ├── ContentView.swift
│   ├── Views/
│   │   ├── ReadyView.swift
│   │   ├── SnapshotTakenView.swift
│   │   ├── ResultsView.swift
│   │   └── SubmitView.swift
│   ├── Models/
│   │   ├── KnowledgeBase.swift
│   │   ├── KBEntry.swift
│   │   ├── Snapshot.swift
│   │   └── DiffResult.swift
│   ├── Services/
│   │   ├── KBFetcher.swift
│   │   ├── SnapshotRunner.swift
│   │   ├── DiffEngine.swift
│   │   └── SubmissionService.swift
│   └── Resources/
│       └── setshot.sh            ← the existing shell script, bundled
└── SetShot.xcodeproj/
```

---

## Knowledge Base Schema

Each entry in `settings-kb.json` follows this schema:

```json
{
  "id": "finder.ShowPathbar",
  "domain": "com.apple.finder",
  "key": "ShowPathbar",
  "source": "defaults",
  "value_type": "bool",
  "description": "Shows the path bar at the bottom of Finder windows, displaying the full folder path to the current location.",
  "ui_location": "Finder → Settings → Advanced → Show path bar",
  "settings_url": "x-apple.systempreferences:com.apple.Finder-Settings.extension",
  "noise": false,
  "noise_reason": null,
  "min_macos": "10.9",
  "notes": null,
  "ai_generated": false,
  "contributed_by_issue": null
}
```

`source` values: `defaults`, `plist`, `tcc`, `pmset`, `scutil`, `networksetup`, `systemsetup`

`value_type` values: `bool`, `int`, `float`, `string`, `date`, `data`

---

## App Architecture

### Application type
Single-window SwiftUI app. Not a menu bar app. Launched on demand, quit when done.

### Window states

**Ready** — app has just launched or a previous session was cleared. One button: Take Before Snapshot. Brief explanation of the workflow.

**Snapshot taken** — a before snapshot exists. Two buttons: Take After Snapshot, Start Over. Shows when the before snapshot was taken.

**Results** — both snapshots exist and the diff has been run. Shows three sections:

1. *Recognised changes* — each entry shows the description, the UI location breadcrumb, and (if `settings_url` is non-null) an Open in Settings button.
2. *Unrecognised changes* — raw diff lines that had no KB match. Each has a Submit button that opens the review/submission flow.
3. *Suppressed noise* — collapsed by default, expandable. Shows entries that were filtered out as noise.

### Submission flow

When the user taps Submit on an unrecognised change:
1. A sheet appears showing exactly what will be submitted: the domain, key, before value, after value, macOS version. No other data.
2. The user can cancel or confirm.
3. On confirm, the app POSTs to the Cloudflare Worker. A spinner shows during the request.
4. On success, the item moves to a "Submitted — thank you" state and the Submit button is replaced with a checkmark.
5. On failure, an error message appears with a Retry option.

### KB fetching

On launch, the app fetches `version.json` from the raw GitHub URL. If the version number is higher than the locally cached version (stored in UserDefaults), it fetches `settings-kb.json` and replaces the cache. The local cache is always used for the actual lookup — never a live fetch at diff time.

If the version fetch fails (no network), the app uses the cache silently. If there is no cache at all, the app shows a one-time warning that KB lookup is unavailable but proceeds — raw diffs are still shown and submittable.

### Security constraints (enforced in Swift, not in KB data)

- `settings_url` values are validated before use: must begin with exactly `x-apple.systempreferences:`, must not contain `://` after the scheme prefix, must not contain whitespace. Any value failing validation is silently ignored and the Open in Settings button is not shown.
- All KB string fields are treated as display-only. None are passed to any execution context other than `settings_url` through the above allowlist.
- The KB URL is hardcoded in the app as a constant. It is not configurable by users or by the KB itself.
- The Worker URL is hardcoded in the app as a constant.

---

## Cloudflare Worker

The Worker code (to be written by a Code session) accepts POST requests with this JSON body:

```json
{
  "domain": "com.apple.finder",
  "key": "ShowPathbar",
  "source": "defaults",
  "before_value": "0",
  "after_value": "1",
  "macos_version": "15.3.1"
}
```

It performs these steps in order:
1. Reject non-POST requests with 405.
2. Parse and validate the JSON body. Required fields: `domain`, `key`, `source`, `before_value`, `after_value`, `macos_version`. All must be strings. Reject if any are missing, not strings, over 500 characters, or contain URL patterns or HTML.
3. Rate-limit by IP: maximum 5 submissions per hour. Reject with 429 if exceeded.
4. Format the issue body as a JSON code block containing the submission data plus a timestamp and a `status: pending` field.
5. POST to the GitHub Issues API using the `GITHUB_TOKEN` secret to create an issue in the `GITHUB_REPO` repo. Title format: `[Submission] domain :: key`.
6. Return 200 on success, 502 on GitHub API failure.

The Worker never returns details about why a submission was rejected beyond the HTTP status code — no information leakage about validation rules.

---

## GitHub Actions Workflow

File: `.github/workflows/process-approved.yml`

```yaml
name: Process Approved Submission

on:
  issues:
    types: [labeled]

jobs:
  process:
    if: github.event.label.name == 'approved'
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          token: ${{ secrets.KB_WRITER_TOKEN }}

      - name: Extract and validate submission
        id: extract
        run: |
          BODY='${{ github.event.issue.body }}'
          # Extract JSON from code block
          JSON=$(echo "$BODY" | sed -n '/^```json/,/^```/p' | grep -v '```')
          
          # Validate required fields exist
          for field in domain key source before_value after_value macos_version; do
            echo "$JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); assert '$field' in d" \
              || (echo "Missing field: $field" && exit 1)
          done
          
          echo "submission=$JSON" >> $GITHUB_OUTPUT

      - name: This step is a placeholder for the KB entry
        # The actual KB entry JSON is produced by the Cowork curation session,
        # not by this workflow. This workflow only runs after Cowork has already
        # edited settings-kb.json and version.json and committed them.
        # See Cowork Curation Session section for the full flow.
        run: echo "Workflow triggered — curation handled by Cowork session"

      - name: Close issue
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.KB_WRITER_TOKEN }}
          script: |
            await github.rest.issues.update({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              state: 'closed'
            });
            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: 'This submission has been processed and incorporated into the knowledge base.'
            });
```

**Note:** The GitHub Actions workflow's main job is issue housekeeping — closing processed issues and leaving a comment. The actual KB writing is done by the Cowork session directly (see below), which gives you interactive review before anything is committed.

---

## Cowork Curation Session

### When to run
Whenever you want to process pending submissions. There is no required schedule. Run it when the mood strikes or when you notice issues have accumulated.

### What to say to start it
Open a Cowork session and paste:

```
Process pending SetShot KB submissions. 
GitHub repo: your-username/setshot-kb
GitHub token: [paste setshot-cowork token]
KB file location: [path to setshot-kb on your Mac]
```

### What Cowork does
1. Fetches all open issues from `setshot-kb` with no label or a `pending` label.
2. For each issue, extracts the submission JSON from the issue body.
3. Reads `prompts/interpret-diff.md` from the repo.
4. Sends all submissions to Claude in one batch, using the prompt, and receives candidate KB entries.
5. Presents a review screen showing all candidate entries — domain, key, description, UI location, settings URL, noise status. One interaction, all entries visible at once.
6. You approve all, approve individually, or reject specific entries.
7. For approved entries, Cowork:
   - Appends them to `settings-kb.json`
   - Increments the version number in `version.json` and updates `updated_at`
   - Fills in `contributed_by_issue` with the GitHub issue number
   - Commits and pushes the changes
   - Labels each processed issue `approved` (triggers the Actions workflow to close it)
8. Rejected entries are labeled `needs-review` and left open for you to examine manually later.

### What you review
For each candidate entry you see:
- The original raw diff line so you can sanity-check the interpretation
- The plain-English description Claude produced
- The UI location breadcrumb
- The settings_url (if any)
- Whether Claude flagged it as noise

You are checking: does the description make sense? Is the UI location plausible? Does anything look wrong? You do not need to understand the underlying plist key to make this judgment — you're evaluating the English output, not the raw data.

---

## Development Sequence

Complete manual setup steps 1–10 first. Then proceed in this order:

1. **Code session** — Write the Cloudflare Worker code and deploy it to the target created in manual step 8.
2. **Code session** — Generate the Xcode project scaffold: SwiftUI app, folder structure, placeholder views.
3. **Cowork session** — Move the generated files into the `setshot-app` folder, open the project in Xcode, confirm it builds.
4. **Code session** — Implement KB fetching and caching (`KBFetcher.swift`).
5. **Code session** — Implement snapshot running (shell script invocation) and diff engine.
6. **Code session** — Implement the results view with recognised/unrecognised/noise sections.
7. **Code session** — Implement the submission flow and Worker integration.
8. **Cowork session** — End-to-end test: take two snapshots with a planted canary value, verify it appears in results, verify submission flow reaches GitHub issues.
9. **Code session** — Seed the KB with the confirmed-working entries from the original SetShot testing (Private Relay, three-finger drag, Reduce Motion, Stage Manager, TCC permissions, Focus modes, scroll bar visibility, natural scrolling, Siri, App Store update settings, font smoothing, Control Center items, notification settings, firewall).
10. **Cowork session** — Run the first real curation batch against any issues that have accumulated during development.

---

## Things Not in Scope for V1

- Auto-update mechanism for the app itself (manual download of new releases is fine to start)
- Sudo-elevated captures for Night Shift, Wi-Fi per-network settings, new-style Login Items
- Default browser / mail client detection (requires adding LaunchServices path to the script)
- Distribution outside your own machines (no code signing / notarisation required for personal use)
- A public website or documentation beyond the repo README

These are all straightforward additions once V1 is working.
