## 1.0b23

- **macOS updates now appear as recognized changes** — When macOS is updated between two snapshots, the new version and build number appear as recognized changes in the comparison, so you can tell which update happened.

- **Software Updates setting** — A new Software Updates section in Settings lets you toggle automatic update checking on or off at any time. Previously, this was only configurable at first launch.

- **Fixed: Automatic updates and "Check for Updates" not working** — The hourly update check interval was not reaching the app, so Sparkle was checking only once a day. Check for Updates also sometimes showed a progress spinner that never completed on macOS 26. Both are fixed. I hope.

- **Fixed: "Delete scheduled snapshots with no changes" preference reset on upgrade** — Users who had previously left that setting unchecked found it turned on after upgrading to 1.0b22. SetShot now detects and preserves your prior preference when upgrading.

- **Fixed: Sleep timer appeared as spurious recognized change** — On systems with many processes preventing sleep, a truncated `pmset` output line could make the sleep timer look like it changed on every scheduled snapshot. Fixed.

- **Knowledge base updates** — Suppressed duplicate Bluetooth trackpad gesture entries that were mirroring their built-in counterparts; added four-finger trackpad swipe gestures; added several power management settings (GPU switching, display dimming, standby delay, automatic restart after power failure, and more); improved App Icon Style labeling.

## 1.0b22

- **Redesigned snapshot list** — The snapshot library now uses a single list for all snapshots. Each row shows a brief summary of the recognized changes found since the previous snapshot, along with a count. Rows with no recognized changes say so explicitly — either "No recognized changes" or "X unrecognized change(s)" — so you can get a sense of what a comparison found.

- **New selection mechanics** — Click any snapshot to select it (shown with a checkmark). Click a second snapshot to form a Before/After pair — whichever is higher in the list is After, whichever is lower is Before. If you already have two selected and click a third, both are deselected and the new one gets the checkmark so you can build a fresh pair. Command-click to force-select a snapshot as Before, and Shift-click to force-select a snapshot as After.

- **Baseline snapshot improvements** — Built-in baseline snapshots are now labeled "macOS Sequoia 15.7.7 baseline defaults" (and similarly for Tahoe) for clarity, and appear in the same style as your own snapshots.

- **Auto-delete empty scheduled snapshots now defaults to on** — The setting to automatically remove scheduled snapshots with no changes was supposed to default to on, but was defaulting to off due to a missing preference value. Fixed.

- **Selectable text in Submit and Feedback sheets** — The setting summary in the Submit and Submit Feedback sheets can now be selected and copied.

- **Knowledge base updates** — Added energy settings (sleep timers, display sleep, Power Nap, standby delay, and more); added Allow Handoff; improved noise filtering for chronod and power management entries that were previously blanket-suppressed.

## 1.0b21

- **Smarter display of Finder new window setting** — Instead of showing cryptic codes like PfCm or PfLo, SetShot now shows your actual Mac name, home folder name, startup volume name, or the name of a custom folder you've chosen.
- **Current macOS alert sound names** — macOS 15 renamed most of the built-in alert sounds (Submarine → Submerge, Morse → Pong, Funk → Funky, etc.). SetShot now shows the current names rather than the legacy ones.
- **Journal search improvements** — Searching the journal now looks at setting values and your notes in addition to setting names and locations. The list also scrolls back to the top when you type a new search.
- **Fixed: Submit Feedback required at least one issue to be checked** — Typing in the notes field alone was enough to enable the Submit button, but clicking it would fail. Now the button stays disabled until you check at least one checkbox.
- **Fixed: Comparison from a notification could show incomplete results** — In some cases, clicking a SetShot notification to view a comparison would open the results before the knowledge base had finished loading, causing recognized changes to appear as unrecognized. This no longer happens.
- **Baseline improvement** — The built-in baseline snapshots were captured on a virtual machine and contained VM-specific computer names, which would appear as spurious "before" values in comparisons. These have been replaced with "not set."
- **Knowledge base updates** — Improved UI location labels throughout, correct Battery / Energy and Lock Screen paths for desktop Macs, and many new noise filters.

## 1.0b19

- **Check for Updates fix** — "Check for Updates" in the SetShot menu was incorrectly greyed out. Fixed.

## 1.0b18

- **Journal notes** — Click **Add note…** at the bottom of any journal entry to add a personal annotation. Notes save automatically when you click away and appear in HTML exports.
- **Journal HTML export** — Click **Export HTML…** next to **Clear All** to save your entire journal as a portable HTML file you can open in any browser.
- **Selectable text** — Text throughout the app can now be selected and copied.
- **About view search** — Use the search field in the About view to find specific help topics, with navigation between matches.
- **First-time changes** — Recognized settings that appear for the first time (with no value in the before snapshot) are shown in an expandable section in the comparison window, keeping the main results focused while still making first-time values accessible. The window automatically expands to make them easier to read.
- **Optional Data Sources** — Music App Settings and App Privacy Permissions capture are now opt-in. Enable them in **Settings → Optional Data Sources** when you want them; SetShot no longer requests these permissions automatically on first launch. Without them, SetShot merely captures fewer settings.
- **First snapshot change count** — The first snapshot no longer counts the number of changes from the baseline.
- **Desktop Mac improvements** — Battery-specific settings (sleep timers, charge limit, battery menu bar icon, etc.) no longer appear as recognized changes on desktop Macs without a battery.
- **More recognized settings** — Added Bluetooth Sharing (file receiving behavior, remote browsing permissions), Content Caching (cache size in GB, cache location, Share Internet Connection), Remote Login (Allow Full Disk Access for Remote Users), and Internet Sharing (source and target interfaces) to the knowledge base.

## 1.0b17

- **Knowledge base feedback** — Click **Submit Feedback** on any recognized change row to report issues with descriptions, System Settings paths, icons, or value formatting. Your feedback helps improve SetShot for everyone!
- **Journal management** — Use **Clear All** to delete the entire journal (with confirmation), or Control-click a section header to remove all entries from a single comparison.
- **Snapshot change counts** — Each snapshot in the library now shows how many recognized changes were found when compared to the previous snapshot.

## 1.0b16

- **Tahoe baseline** — Created a baseline snapshot to macOS 26.5.1 Taheo to replace the placeholder.
- **Recognized changes sorted by Settings pane** — Recognized changes in comparison results are now sorted in the same order as System Settings panes, making it easier to navigate to each one.
- **Knowledge base fixes** — Fixed a KB decode failure that prevented some entries from loading.

## 1.0b15

- **Icon fixes** — Restored missing icons for Screen Saver, Lock Screen, Sound, and Screenshot app after a regression in macOS 15.7.7.

## 1.0b14

- **Base snapshots** — SetShot now includes built-in baseline snapshots for macOS 15.7.7 Sequoia. Compare against a baseline to see how your current settings differ from a clean system.
- **Results HTML export** — Click **Export HTML…** in any comparison window to save the results as a portable HTML file.
- **Eliminated Command Line Tools dependency** — SetShot no longer requires Xcode Command Line Tools to be installed, and no longer triggers a developer tools install prompt.

## 1.0b13

- **USB audio device names** — USB audio devices (external DACs, audio interfaces, and similar hardware) now show their actual model name instead of a raw hardware identifier.
- **UI improvements** — Wider default window width, screenshot assets added to the About help guide, and a fix for a spinner animation that could stall during comparison.

## 1.0b12

- **Settings tab** — Moved the scheduler to a dedicated Settings tab so the main view stays focused on snapshots.
- **About view** — Added a built-in help guide covering all of SetShot's features. 
- **Submit All** — Click **Submit All** in any comparison window to review and send all unrecognized changes at once instead of one at a time.
- **Privacy section** — Added a privacy section to the About view explaining exactly what data SetShot sends and how it is handled.

## 1.0b11

- **macOS version-aware Settings paths** — The System Settings location shown for each recognized change now adapts to reflect the correct name for your macOS version.

## 1.0b10

- **Performance fix** — Capped unrecognized items at 500 and truncated very long values to prevent the comparison window from hanging when a snapshot contained an unusually large number of changes.

## 1.0b9

- **Apple-only domains** — SetShot now filters the settings scan to Apple-owned preference domains only, reducing noise from third-party apps that store settings in Apple-style preference files.

## 1.0b8

- **Voice Control** — Added recognition of the Voice Control enabled/disabled setting.
- **Noise filter improvements** — Suppressed additional macOS-internal values that change on their own without reflecting user-driven preference changes.

## 1.0b7

- **Access prompt fix** — Fixed an issue where the privacy database access prompt appeared on every launch instead of just the first time.

## 1.0b6

- **Crash fix** — Fixed a crash that occurred on launch when no snapshots had been taken yet.

## 1.0b5

- **Journal view** — Added a Journal tab that keeps a cumulative record of every recognized change found across all your comparisons, grouped by comparison date.
- **System Settings icons** — Comprehensive icon coverage for System Settings panes using SF Symbols and custom assets, so recognized changes show the correct pane icon.
- **Journal deduplication** — The journal now automatically removes duplicate entries, so running the same comparison twice doesn't create redundant records.
