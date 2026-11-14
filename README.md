# SetShot 1.0

SetShot takes a snapshot of the macOS settings on your Mac, then compares two snapshots to show what changed and what each change means. Reasons to use it:

* **macOS updates:** Wonder whether a macOS update changed any of your settings? Compare snapshots from before and after.
* **Settings journal:** SetShot maintains a journal of all your settings so you can see what changed and when.
* **Export current setup:** You can compare against a baseline and export a record of everything you've changed, should you want to set up a Mac from scratch using your preferred settings.

**[Download the latest release](https://github.com/adamengst/setshot-app/releases/latest)**

SetShot runs on macOS 13 Ventura and later, and includes baselines of fresh installations of macOS 15 Sequoia, macOS 26 Tahoe, and macOS 27 Golden Gate. Your mileage may vary with other versions.

SetShot is not perfect. Treat surprising reports as an excuse to research further, and remember: SetShot never changes any settings. If something changes unexpectedly, that's macOS at work. The only files SetShot writes are its snapshots, journal, and anything you export. SetShot does not track settings of non-Apple apps.

---

## Taking and comparing snapshots

1. **Take a snapshot** before you change anything. Click **Take Snapshot**, and SetShot captures hundreds of settings across System Settings, accessibility options, network configuration, and more.
2. **Make your changes** by applying an update, installing software, or adjusting preferences.
3. **Take another snapshot** and click **Compare**. SetShot lists the macOS settings that changed between the two.

You can keep as many snapshots as you like and compare any pair, including against the baseline for a new installation of your version of macOS (macOS 15 Sequoia or later), so you can see (and export) everything you've changed from a fresh installation. You can rename snapshots to make them easier to distinguish or delete them if they're unnecessary (likely because they don't show any changes). Snapshots are gzip-compressed, so each takes less than 1 MB.

---

## Comparison results

**Recognized changes** are settings that SetShot's knowledge base knows about. Each one gets a plain-English description, the path to find it in System Settings, and, where possible, an **Open in Settings** button that takes you directly to the relevant pane. Changed values are displayed in readable form: toggles show On or Off, volume shows a percentage, and settings with a fixed list of options (like Hot Corner actions) show the option name rather than a raw number. A **Submit Feedback** button on each row lets you flag issues with the description, path, icon, or values so I can improve the knowledge base.

**Unrecognized changes** are settings not yet in the knowledge base. You can see the raw technical name and its old and new values. A **Submit** button lets you submit unrecognized changes for review and addition to the knowledge base.

---

## The SetShot journal

Journal view keeps a running history of recognized changes from all your comparisons. Click **Journal** to see a timeline of everything that has changed on your Mac. Entries are grouped by comparison, searchable, and can be deleted individually (Control-click for a **Delete Entry** command), by comparison, or all at once with the **Clear All** button.

---

## Automatic snapshots

SetShot can take snapshots on a schedule — every N minutes or hours, daily, weekly, or monthly. Click **Settings** to configure it. Snapshots happen in the background without the app window appearing, and they accumulate into a history. When a scheduled snapshot finds recognized changes, a notification appears; click it to open the comparison.

The first time you enable automatic snapshots, macOS will ask for Notifications permission so SetShot can alert you to changes.

---

## Permissions

By default, SetShot takes snapshots without requesting any special permissions. Two optional data sources, available in **Settings → Optional Data Sources**, expand what SetShot captures if you turn them on:

* **Music App Settings** — reads Music, Home Sharing, and related preferences. macOS will show a **Media & Apple Music** permission dialog the first time a snapshot runs after you enable it; click **Allow**. macOS remembers your choice.
* **App Privacy Permissions** — detects which apps have been granted access to the microphone, camera, contacts, and similar resources. To do this, SetShot requires **Full Disk Access**, which you can grant from the same Settings pane or in **System Settings → Privacy & Security → Full Disk Access**.

Neither is required. Without them, SetShot captures fewer settings and everything else works normally.

---

## Getting help

For anything that isn't about a single setting (a question about how SetShot works, a problem with the app, or an idea for a new feature), choose **Help → Contact Support**. Pick **Bug Report**, **Question**, or **Suggestion**, describe what you need, and click **Send**. If you'd like a reply, enter your name and email address; they're used only to answer that message.

---

## Privacy

The data SetShot works with is system settings such as toggles, sliders, and preferences, not passwords, documents, photos, or personal content, so it is inherently non-sensitive. SetShot still keeps it private.

* **Snapshots, comparisons, and journal entries** are stored only on your Mac and are never transmitted anywhere.
* **Submissions** are different. When you submit an unrecognized change or send feedback on a recognized change, the relevant setting data is sent to me over a secure connection and stored privately, along with anything you type into the notes field. SetShot does not collect any identifying information unless you choose to provide it there. Submissions are entirely opt-in. Support messages sent with **Help → Contact Support** are handled the same way, along with your name and email address if you include them, which are used only to reply to that message. As with any Internet connection, your IP address is seen by the service that handles submissions (Cloudflare) but is not stored in your submission record.

SetShot is open source. If you want to verify what data the app collects and how it is handled, the full source code is available at [github.com/adamengst/setshot-app](https://github.com/adamengst/setshot-app). Use SetShot at your own risk.

---

SetShot is designed by Adam Engst, coded by Claude Code, and published by [TidBITS Publishing](https://tidbits.com).
