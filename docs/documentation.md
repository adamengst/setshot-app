# About SetShot

Have you ever thought a macOS update changed some setting silently? Or have you spelunked through System Settings and wondered later what you clicked? With SetShot, you can find out what settings have changed over time, making it easy to see what you've done and revert inadvertent changes.

SetShot lets you capture a complete snapshot of your Mac's settings at any point in time so you can compare any two snapshots and see exactly what changed, in plain English. Each recognized change comes with a description, its location in System Settings, and — where possible — a button that opens the exact pane directly.

**TL;DR:** To use SetShot, click **Take Snapshot**, make some changes in System Settings, take another snapshot, select both snapshots, and click **Compare**. For full background and detailed instructions, read on.

## SetShot Views

SetShot has four views, accessed by clicking the buttons at the top of the window:

![The four view buttons at the top of the SetShot window](images/ScreenshotNavigation.png)

- **Snapshots:** Shows all the snapshots you've taken in a single list, newest first.
- **Journal:** A chronological log of all recognized changes across your comparisons.
- **Settings:** Reverse sort order and set up automatic daily snapshots.
- **About:** You're reading it now.

## Taking Snapshots

SetShot's core function is to take and compare snapshots. To that end, it scans around 450 settings files across 20 system data sources. It currently recognizes over 780 settings and knows to ignore over 1600 additional changes that are just macOS noise.

To take a snapshot of the current state of your Mac's settings, click **Take Snapshot** at the bottom of the Snapshots view. SetShot saves the result to the snapshot library with the date and time. Snapshots are stored in `~/Library/Application Support/SetShot/snapshots` as gzipped files that occupy little space. Capturing typically takes less than a minute.

Each snapshot line shows when the snapshot was taken, a brief summary of the first few recognized changes from the previous snapshot, the number of recognized changes from the previous snapshot, and the size of the snapshot file.

![The snapshot library with a context menu open](images/ScreenshotSnapshotsContext.png)

If you wish, you can rename a snapshot. Control-click it and choose **Rename**, then type a new name. Renaming can be useful for labeling snapshots with context — for example, ‘Before macOS 26.7’ or ‘After Accessibility testing.’

If a snapshot is superfluous — perhaps because it shows no changes — you can delete it. Control-click it and choose **Delete**.

## Comparing Snapshots

Once you've taken at least two snapshots, SetShot can compare them.

The Snapshots view shows all your snapshots in a single list. Click any two snapshots to select them — the topmost selected is always **After** and the bottommost is always **Before** (reversed if you've turned on **Show oldest first** in Settings). Clicking a third snapshot replaces one of the current selections based on position. Click a selected snapshot to deselect it. Command-click to force-select a snapshot as **Before**; Shift-click to force-select it as **After**.

![Two snapshots selected and ready to compare](images/ScreenshotSnapshotsReady.png)

After selecting both snapshots, click **Compare** to run the comparison. The results open in a new window titled with the names of the two snapshots, leaving the snapshot library available so you can start additional comparisons. You can have multiple comparison windows open at once to look at them side by side.

SetShot identifies every setting that differs between the two snapshots and looks up each one in its knowledge base to determine whether it's a recognized change or an unrecognized change. Changes to the knowledge base are read at every launch.

## Understanding Results

Results are divided into two sections:

- **Recognized Changes:** Settings already in SetShot’s knowledge base. Each entry shows a plain-English description, the path to find it in System Settings, and — where possible — an **Open in Settings** button that takes you directly to the relevant pane. The old value appears in orange and the new value in blue. A **Submit Feedback** button lets you flag issues with the description, path, icon, or value formatting to help improve SetShot for everyone.
- **Unrecognized Changes:** Changes that are either noise or legitimate settings changes that aren't yet in the knowledge base. The raw technical name of the setting is shown along with its old and new values. You can submit these to help improve SetShot for everyone.

Values are displayed in a readable form where possible: toggles show On or Off, volume settings show a percentage, file paths show just the filename, and settings with a fixed list of options (like Hot Corner actions) show the option name rather than a raw number.

![A comparison window showing recognized and unrecognized changes](images/ScreenshotResults.png)

## The Journal

The journal keeps a cumulative record of every recognized change found across all your comparisons. Switch to it by clicking **Journal** in the segmented control at the top of the SetShot window.

Journal entries are grouped by comparison, with a header showing the date and time of the comparison and how many recognized changes it found. Each entry shows the setting description, its location in System Settings, and the before-and-after values. An **Open in Settings** button appears when possible.

To add a personal note to any entry, click **Add note…** at the bottom of the row and type. Your note is saved automatically when you click away.

Use the search field at the top to filter entries by description, setting name, location, or note. To delete an entry, Control-click it and choose Delete. You can also Control-click a section header and choose Delete to remove all entries from that comparison at once. Click **Export HTML** to save the entire journal as an HTML file, or **Clear All** to permanently delete all entries (you'll be asked to confirm).

The journal automatically eliminates redundant entries: if the same change appears more than once — for instance, if you run the same comparison twice — only the earliest occurrence is kept.

![The journal view](images/ScreenshotJournal.png)

## Submitting Unrecognized Changes

When you find an unrecognized change that is either noise or that you think should be included in the knowledge base, click **Submit** on that row. A confirmation sheet shows exactly what data will be sent — the internal setting name, its old and new values, and your macOS version — and nothing else.

The sheet also offers an optional feedback section. If you have a sense of what the change represents, select one of the two categories:

- **Expected settings change:** The change reflects something real — a preference you set, a feature you turned on, or a setting macOS adjusted as a result of something you did.
- **Likely macOS noise:** The change appears to be an internal macOS value that fluctuates on its own, unrelated to any setting you'd want to track.

You can also add a short note with any context that might help with review. Both fields are entirely optional, but adding context may help categorize the change more accurately.

![The sheet for submitting an unrecognized change](images/ScreenshotSubmitUnrecognized.png)

If you have several unrecognized changes, click **Submit All** to review and send them all at once. Submitted changes are reviewed, added to the knowledge base, and loaded on the next launch, making SetShot more useful for everyone.

Already-submitted rows are marked with a checkmark for the duration of the session.

## Improving Recognized Changes

Even recognized changes can have room for improvement: an icon may be missing, a description may be unclear, a System Settings path may be wrong, or values may show as raw numbers instead of readable labels.

Click **Submit Feedback** on any recognized change row to open a feedback sheet. Check the issues that apply, add any notes that might help, and click **Submit**. The sheet shows a summary of the current description and location so you can refer to them while writing.

![The feedback sheet for a recognized change](images/ScreenshotSubmitRecognized.png)

Feedback is reviewed and incorporated into future knowledge base updates, making SetShot more accurate for everyone.

## Automatic Snapshots

SetShot can take snapshots automatically on a schedule. Click **Settings** in the segmented control at the top, then select **Take automatic snapshots** and choose how often: every N minutes, every N hours, once a day, once a week, or once a month. For day, week, and month intervals, you can also set the time of day.

Automatic snapshots are taken silently in the background without SetShot's window appearing (though you may see it appear and disappear from the dock). This lets you build up a history of your Mac's settings over time without having to remember to capture manually.

When you enable automatic snapshots, macOS will ask for **Notifications** permission. If granted, a notification appears whenever a scheduled snapshot finds recognized changes; clicking it opens the comparison in SetShot.

It would be smart to keep **Delete scheduled snapshots with no changes** enabled to automatically remove snapshots taken by the scheduler that found no changes, keeping your library uncluttered.

![The Settings view](images/ScreenshotSettings.png)

## Optional Permissions

By default, SetShot takes snapshots without requesting any special permissions. Two optional data sources in **Settings → Optional Data Sources** expand what SetShot captures:

- **Music App Settings:** When enabled, SetShot reads Music, Home Sharing, and related preferences. macOS will display a **Media & Apple Music** permission dialog the first time a snapshot runs — click **Allow**. This permission is remembered permanently.

  ![The Media & Apple Music permission dialog](images/PermissionMusicAccess.png)

- **App Privacy Permissions:** When enabled, SetShot reads the system privacy database to detect which apps have been granted access to the microphone, camera, contacts, and similar resources. This requires **Full Disk Access** — grant it in **System Settings → Privacy & Security → Full Disk Access**, or use the button in Settings → Optional Data Sources.

One more permission is used when automatic snapshots are enabled:

- **Notifications:** When you enable automatic snapshots in Settings, macOS will ask for Notifications permission. If granted, a notification appears whenever a scheduled snapshot finds recognized changes; clicking it opens the comparison.

## Privacy

The data SetShot works with is inherently non-sensitive — it's system settings like toggles, sliders, and preferences, not passwords, documents, photos, or personal content. That said, SetShot is designed to keep your data private.

- **Snapshots, comparisons, and journal entries** are stored only on this Mac and are never transmitted anywhere.
- **Submissions** are the one exception. When you submit an unrecognized change or send feedback on a recognized change, the relevant setting data is sent to the developer over a secure connection and stored privately. Submissions are entirely opt-in. As with any Internet connection, your IP address is seen by the service that handles submissions (Cloudflare) but is not stored in your submission record.

SetShot is open source. If you want to verify exactly what data the app collects and how it is handled, the full source code is available at [github.com/adamengst/setshot-app](https://github.com/adamengst/setshot-app).
