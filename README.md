# SetShot 1.0 beta

SetShot captures a comprehensive snapshot of your Mac's settings, then lets you compare two snapshots to see exactly what changed and what each change means. Why might you want to do this?

* **macOS updates:** Have you wondered if a macOS update has changed any of your settings? Now you can know!
* **Settings journal:** SetShot maintains a journal of all your settings so you can see what changed and when.
* **Export current setup:** You can compare against a baseline and export a record of everything you've changed, should you want to set up a Mac from scratch using your preferred settings.

**[Download the latest release](https://github.com/adamengst/setshot-app/releases/latest)**

Tested with macOS 15 Sequoia and macOS 26 Tahoe. Your mileage may vary with other versions.

---

## How SetShot works

1. **Take a snapshot** before you make changes — click Take Snapshot and SetShot captures hundreds of settings across System Settings, accessibility options, network configuration, default app handlers, and more.
2. **Make your changes** — apply an update, install software, adjust preferences, whatever you want to track.
3. **Take another snapshot** and click **Compare**. SetShot shows you every setting that changed between the two.

You can keep as many snapshots as you like and compare any pair, including against the baseline for a new installation of your version of Sequoia or Tahoe. Snapshots can be renamed to make them easier to distinguish or deleted if they're unnecessary. They're stored in compressed format so they don't take up much space (less than 1 MB each).

---

## What you see in results

**Recognized changes** are settings that SetShot's knowledge base knows about. Each one gets a plain-English description, the path to find it in System Settings, and — where possible — an **Open in Settings** button that takes you directly to the relevant pane. Changed values are displayed in readable form: toggles show On or Off, volume shows a percentage, and settings with a fixed list of options (like Hot Corner actions) show the option name rather than a raw number. A **Submit Feedback** button on each row lets you flag issues with the description, path, icon, or value formatting so we can improve the knowledge base.

**Unrecognized changes** are settings not yet in the knowledge base. You can see the raw technical name and its old and new values. A **Submit** button lets you submit unrecognized changes for review and addition to the knowledge base, where they improve everyone's experience.

---

## The SetShot journal

Journal view keeps a running history of recognized changes from all your comparisons. Flip to the journal to see a timeline of everything that has changed on your Mac. Entries are grouped by comparison, searchable, and can be deleted individually (Control-click for a Delete command), by comparison, or all at once with the **Clear All** button.

---

## Automatic snapshots

SetShot can take snapshots on a schedule — every N minutes or hours, daily, weekly, or monthly. Click **Settings** to configure it. Snapshots are taken silently in the background without the app window appearing, building up a history automatically. When a scheduled snapshot finds recognized changes, a notification appears; click it to open the comparison.

The first time you enable automatic snapshots, macOS will ask for **Notifications** permission so SetShot can alert you to changes.

---

## Permissions

On your first snapshot, macOS will ask for **Media & Apple Music** access — click Allow. SetShot needs it to read music-related settings such as Home Sharing and library configuration.

Optionally, granting **Full Disk Access** (in System Settings → Privacy & Security) lets SetShot detect changes to app permission settings, such as an app gaining microphone or camera access, and also eliminates the Media & Apple Music dialog. Without it, SetShot simply skips that one data source.

---

## Privacy

The data SetShot works with is inherently non-sensitive—it's system settings like toggles, sliders, and preferences, not passwords, documents, photos, or personal content. That said, SetShot is designed to keep your data private.

* **Snapshots, comparisons, and journal entries** are stored only on your Mac and are never transmitted anywhere.
* **Submissions** are the one exception. When you submit an unrecognized change or send feedback on a recognized change, the relevant setting data is sent to the developer over a secure connection and stored privately. Submissions are entirely opt-in. As with any Internet connection, your IP address is seen by the service that handles submissions (Cloudflare) but is not stored in your submission record.
* **Full Disk Access:** SetShot appears in the Full Disk Access list in System Settings, but it must be turned on manually. Granting Full Disk Access allows SetShot to query the system privacy database to detect changes to app permission settings (for example, if you grant an app microphone access). Full Disk Access is not required—without it, SetShot simply skips that one data source, and everything else works normally.

SetShot is open source. If you want to verify exactly what data the app collects and how it is handled, the full source code is available here.

---

SetShot is designed by Adam Engst, coded by Claude Code, and published by [TidBITS Publishing](https://tidbits.com).
