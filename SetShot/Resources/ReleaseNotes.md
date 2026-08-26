## 1.0b27

- **Privacy permissions are now tracked** — SetShot reports when an app gains or loses Full Disk Access, Media & Apple Music, camera, microphone, contacts, screen recording, accessibility, and around twenty other permissions, naming the app and the permission. This needs Full Disk Access for SetShot itself; a new button in Settings → Optional Data Sources opens the right pane, suggested by Chris Pepper.

- **Security settings are now tracked** — System Integrity Protection, Gatekeeper, FileVault and the firewall were captured in every snapshot but never appeared in a comparison, because they were recorded in a form SetShot could not read back. All four report properly now, as do the time zone and the network time server.

- **Wallpaper and screen saver changes are now tracked** — Including per-display wallpapers, which is what you get when "Show on all Spaces" is turned off. Built-in wallpapers and aerials show their names — Sequoia Sunrise, Palau Jellies — instead of file paths or asset identifiers, displays are named the way System Settings names them, and placement reads Fill Screen or Center rather than a number.

- **Sound output and input devices are tracked** — Which device sound plays through and records from. macOS keeps no record of this on disk — the audio preference files hold per-device settings but nothing naming the active one — so connecting AirPods could switch every Sound setting on screen while a comparison reported nothing. It changes whenever a device is connected or disconnected, not only when you choose one.

- **More settings tracked** — Default Web browser and email client, launch agents and daemons, DNS servers, proxies and network services, Time Machine destinations, system extensions, configuration profiles, and whether the startup chime plays.

- **Permission changes no longer bury a comparison** — Granting or revoking Full Disk Access or Media & Apple Music changes what SetShot can read, not what is set on your Mac. Revoking Full Disk Access used to report Time Machine as switched off and Mail's settings as wiped; turning off Media & Apple Music reported numerous Music and TV settings as deleted. SetShot now reports the permission change itself and says that anything appearing in only one snapshot reflects what it could read.

- **Comparisons across versions are flagged** — Snapshots now record which capture format they used. Comparing a snapshot taken by b26 or earlier against a newer one shows a note explaining that some of the changes are the older snapshot recording the same settings in an older way, rather than anything on your Mac changing. Your existing snapshots still compare against each other normally.

- **Clearer values throughout** — Trackpad click pressure, Full Keyboard Access, the dictation shortcut, notification sort order, the battery indicator and around twenty other settings show the names System Settings uses instead of raw numbers, and apps show their names instead of bundle identifiers.

- **Fixed: firewall changes were reported as nonsense** — Turning the firewall on or off produced two entries with garbled names instead of one change, because the state was recorded in a form the comparison could not read.

- **Fixed: submissions failed with no explanation** — A submission whose notes contained a link, text in angle brackets, or more than 1000 characters was refused, and the sheet said only "Submission failed. Please try again" — advice that could not work, since the same text always failed. SetShot now checks before sending and says what to change.

- **Fixed: feedback containing angle brackets was rejected** — A submission whose notes contained something like `<name@example.com>` was refused, and the sheet said only "Submission failed. Please try again." The check meant to block HTML tags was matching any angle brackets with a letter after the first one.

- **Fixed: Submit Feedback failed for some settings** — Feedback on anything covered by a general knowledge base entry — privacy permissions, launch agents, wallpaper, network services — was rejected before it reached me.

- **Fixed: Music and TV settings stopped being captured after granting access** — Granting Media & Apple Music left capture switched off until you happened to open SetShot's Settings. It now follows the permission directly. There is also a button to reopen that pane once you have answered the prompt, which previously left no way back.

- **Fixed: the folder for new Finder windows showed the wrong value** — When set to a custom folder, both sides of a comparison showed today's folder rather than what each snapshot recorded, so changing from one custom folder to another reported nothing at all.

- **Export as Markdown** — Export HTML in comparisons and in the Journal is now an Export menu offering HTML or Markdown. The Markdown is plain text with a checkbox for each change, so it reads in any editor and can be diffed between two Macs to see what differs. Suggested by Chris Pepper.

- **Exports are named after the Mac and the date** — A comparison used to save as something like "SetShot — media-on vs Today at 16:06.html", which names no machine and stops meaning anything the next day, and the Journal always saved as "SetShot Journal.html". Both now include the computer name and a sortable date, so exports from two Macs can sit in the same folder. Suggested by Chris Pepper.

- **Escape clears a search field** — In the Journal, About and Release Notes search fields, pressing Escape now empties the field, the same as clicking the x beside it. Suggested by Chris Pepper.

- **Settings has a menu item** — SetShot → Settings, under About SetShot, with the usual Command-comma. The shortcut already worked but nothing in the menus said so, suggested by John Gruber.

- **Fixed: energy settings looked like they changed when you unplugged** — SetShot read these from `pmset -g`, which reports only whichever power profile is live. On a laptop, every energy setting that differs between battery and the power adapter appeared to change the moment the power cord came out — display sleep and Wake for network access both did. Both profiles are now captured separately and labelled "on battery" and "on the power adapter", so switching power sources changes nothing and each profile's setting is reported in its own right. The caveats added in b25 and b26 warning that these settings could look changed just from switching power sources are gone, along with the duplicate rows that reported the same energy setting twice. Desktop Macs, which have only one profile, no longer see the battery settings at all.

- **Fixed: one wallpaper change reported once per Space** — With "Show on all Spaces" turned on, macOS writes the same wallpaper into every Space, so changing it produced an identical "Wallpaper on Built-in Display" entry for each Space you had open — twenty entries for one change on my Mac. Spaces that recorded the same before and after now collapse to one entry per display; Spaces that genuinely held different wallpapers still report separately. Some of those entries also showed a raw key instead of a description, because the entry macOS writes as the default across Spaces has no Space identifier and the description could not read it.

- **Fixed: unplugging looked like the wallpaper changed** — While a laptop runs on battery, macOS swaps a dynamic desktop or aerial for a still image and switches back on the power adapter, rewriting the system default wallpaper each way. That default is only the fallback for a display with no wallpaper of its own, so nothing on screen changed, but three entries were reported every time the power cord moved. It is now left out when every display has its own wallpaper, and still reported on a Mac that relies on the fallback.

- **Fixed: a Time Machine disk unmounting looked like a settings change** — Where a backup disk happens to be mounted is state, not a setting, but unplugging one reported the mount point vanishing and coming back. A destination genuinely being added or removed still shows.

- **Knowledge base updates** — Around 130 new entries covering privacy permissions, security status, wallpaper, network configuration and background items. Corrected the battery indicator values, which were mislabeled; the Notification Center sort order and Stage Manager grouping, which pointed at controls that either do not exist or only appear when Stage Manager is on; the Lock Screen password hint, which is a switch rather than a retry count in macOS 15; and menu bar clock and battery entries that showed no icon. Described the system font settings, Finder's Quit menu item, grammatical gender, the Spoken Content voice, the TV app appearance, and the Mail sender-domain list; suppressed noise from analytics timestamps, transient Finder view settings, per-Space wallpaper duplication and several daemon flags. Restructured the energy settings so each one is recorded per power profile, and retired the twenty-six duplicate entries that reported the same setting from a second source.

## 1.0b26

- **Update checking now happens only at launch** — Previously, SetShot checked at launch plus on a recurring hourly timer; now it's launch only, since the app is normally opened and closed rather than left running in the background.

- **Updated Sparkle to 2.9.5** — Includes the latest stability and security improvements to the update framework.

- **Fixed: Before/After didn't follow "Show oldest first"** — With that setting enabled, the topmost and bottommost selected snapshots kept the default newest-first roles, so the topmost selection could end up mislabeled After instead of Before. Before/After now correctly flips along with the display order.

- **Knowledge base updates** — Extended the "can look changed just from switching power sources" caveat to nine more Battery → Options settings (computer sleep, display sleep, wake for network access, and others) beyond the one originally reported; suppressed noise from AppKit's automatic menu-item-disabled state, rotating Find My push-notification tokens, and internal on-device speech recognition asset allocation.

## 1.0b25

- **Fixed: Scheduled snapshot summaries sometimes missing** — Scheduled snapshots run as a separate background process, so if SetShot's window was already open, the snapshot list wouldn't show the new comparison's summary until you manually compared that pair — just the bare change count. The list now refreshes summaries whenever the app comes to the foreground.

- **Knowledge base updates** — Fixed the Sound Effects output device and "Allow notifications when the display is sleeping" settings, which were displaying values that didn't match System Settings; added human-readable values for the Zoom scroll-wheel modifier key and suppressed its trackpad-domain duplicate; noted that Battery → Options settings (like hard disk sleep) can look changed just from switching between battery and being plugged in; noted that the default Finder window view can change just from browsing a folder in a different view, not only from deliberately setting a new default; suppressed noise from an internal MDM poll-timer value, a hidden QUIC/HTTP-3 network preference, and an Accessibility key-repeat timing value.

## 1.0b24

- **Recognized changes are no longer hidden** — Settings that appeared "for the first time" between two snapshots used to be tucked into a collapsible section, hidden by default, on the theory they usually indicated false positives (a Full Disk Access grant, macOS reinitializing defaults). That guess was wrong too often — it obscured real changes and had no way to tell an actual first-time change from a setting whose "off" state just isn't recorded. Every recognized change now shows up directly.

- **Automatic cleanup of transient scheduled-snapshot noise** — Scheduled background snapshots occasionally caught macOS in the middle of some sort of reset, showing a batch of changes that flipped back on the next check. SetShot now detects these round-trips, removes the spurious in-between snapshot and its journal entries, and keeps any user-initiated change that landed in the same window.

## 1.0b23

- **macOS updates now appear as recognized changes** — When macOS is updated between two snapshots, the new version and build number appear as recognized changes in the comparison, so you can tell which update happened.

- **Software Updates setting** — A new Software Updates section in SetShot's Settings screen lets you toggle automatic update checking on or off at any time. Previously, this was only configurable at first launch.

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
