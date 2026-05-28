# SetShot 1.0beta

SetShot captures a comprehensive snapshot of your Mac's settings, then lets you compare two snapshots to see exactly what changed and what each change means.

It's designed for situations where you want to know what shifted after a macOS update or a session of tweaking options in System Settings.

**[Download the latest release](https://github.com/adamengst/setshot-app/releases/latest)**

Tested with macOS 15 Sequoia and macOS 26 Tahoe. Your mileage may vary with other versions.

---

## How it works

1. **Take a snapshot** before you make changes — click Take Snapshot and SetShot captures hundreds of settings across System Settings, accessibility options, network configuration, default app handlers, and more.
2. **Make your changes** — apply an update, install software, adjust preferences, whatever you want to track.
3. **Take another snapshot** and click **Compare**. SetShot shows you every setting that changed between the two.

You can keep as many snapshots as you like and compare any pair. Snapshots can be renamed to make them easier to distinguish or deleted if they're unnecessary. They're stored in compressed format so they don't take up much space (~1 MB each).

---

## What you see in results

**Recognized changes** are settings that SetShot's knowledge base knows about. Each one gets a plain-English description, the path to find it in System Settings, and — where possible — an **Open in Settings** button that takes you directly to the relevant pane. Changed values are displayed in readable form: toggles show On or Off, volume shows a percentage, and settings with a fixed list of options (like Hot Corner actions) show the option name rather than a raw number.

**Unrecognized changes** are settings not yet in the knowledge base. You can see the raw technical name and its old and new values. Submit unrecognized changes so they can be reviewed and added to the knowledge base, where they improve everyone's experience.

---

## The journal

Journal view keeps a running history of recognized changes from all your comparisons. Flip to the journal to see a timeline of everything that has changed on your Mac. Entries are grouped by comparison, searchable, and can be deleted individually or by comparison.

---

## Automatic snapshots

SetShot can take snapshots on a daily schedule, silently in the background, without its window ever appearing. Click the gear icon to set a time. This builds up a history automatically so you can always look back at what changed and when.

---

## First launch

On your first snapshot, macOS will ask for permission twice — click Allow each time. These permissions let SetShot read system preferences and media library settings; it doesn't transmit any of this data.

---

## Privacy

Snapshots are stored locally in `~/Library/Application Support/SetShot/snapshots`. When you submit an unrecognized change, SetShot sends only the internal setting name, its old and new values, and your macOS version — nothing else. Submissions are entirely optional.

---

SetShot is published by [TidBITS](https://tidbits.com).
