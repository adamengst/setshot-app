## 1.0b27

- **SetShot offers to move itself to Applications** — If you unzip SetShot and open it from the Downloads folder, macOS runs it from a randomly named copy that it deletes afterward — this "translocation" increases security. Neither automatic snapshots nor updates can work from a translocated copy, so SetShot now spots this at launch and offers to move itself to your Applications folder and reopen from there. Until it has been moved, automatic snapshots and Check for Updates are switched off rather than appearing to work. Thanks to Beatrix Willius for the suggestion.

- **SetShot now distributed via disk image** — Although you can continue to download the Zip-compressed file from GitHub for now, SetShot is now primarily distributed as a disk image. Opening the download shows SetShot, an arrow, and a symlink to your Applications folder in the classic "Drag this to your Applications folder" approach. Doing so avoids the translocation problem above.

- **Snapshots are faster** — SetShot reads about 500 preference files, and it had been launching a fresh copy of itself for each one — nearly a thousand processes to read a megabyte and a half of settings. It now reads them all in one pass. The gain is larger on slower Macs, where starting a process costs more.

- **Comparisons are faster** — Comparing against a built-in baseline in particular could be quite slow and is now notably quicker. The list of things SetShot ignores as noise has grown to some 800 patterns, and checking every line against all of them in one pass was most of the wait; it now runs across all your Mac's cores.

- **Capturing and comparing can be canceled** — Although capturing and comparing snapshots are faster, they're not instant, so you might want to cancel if you clicked accidentally. Press Escape, Command-period (for old Mac users), or Control-C (for Unix users) while the Capturing or Comparing spinner is showing to stop the process. Thanks to Beatrix Willius for the suggestion.

- **Export as Markdown** — The Export HTML button in comparisons and in the Journal has now transmogrified into an Export menu offering HTML or Markdown. The Markdown is plain text with a checkbox for each change, so it reads in any editor and can be compared between two Macs to see what differs. Suggested by Chris Pepper.

- **Exports are named after the Mac and the date** — Comparison and Journal exports now include the computer name and a sortable date, so exports from two Macs can live in the same folder. Another one from Chris Pepper.

- **Release notes appear when an update is offered** — The update window now shows the release notes in a scrolling panel so you can see what's new before installing. What a concept.

- **Comparison windows no longer hide each other's titles** — Opening several comparisons stacked them slightly too tightly, so each new window covered some of the title of the one behind it. Each now sits a full title bar below the last.

- **About shows when the build was made** — The About window now shows the date the build was made, which I needed to differentiate between test builds. You probably don't care.

- **Settings has a menu item** — John Gruber and Simon both gave me friendly grief about how an app designed to report on settings lacked a Settings menu item. I had left it out because Settings has its own view in the main window, but there's now a SetShot → Settings menu item with the usual Command-comma shortcut. The shortcut had been there before to assuage your muscle memory, but now the SetShot menu looks right, too.

- **The View menu is gone** — Beatrix Willius pointed out that the contents of the default View menu were of no utility. Doh! It's now an ex-menu.

- **Escape clears search fields** — In the Journal, About, and Release Notes search fields, pressing Escape now empties the field, the same as clicking the x beside it. Chris Pepper, you're welcome.

- **Refined app icon** — Scott pointed out some crudeness in the ChatGPT-generated SetShot icon. I scolded ChatGPT into improving it so it's the same size as other Mac icons and a little smoother.

- **Fixed: submissions failed with no explanation** — SetShot would refuse a submission whose notes contained a link, text in angle brackets, or more than 1000 characters, saying only, "Submission failed. Please try again." SetShot now checks before sending and says what to change.

- **Comparisons across versions are flagged** — It was necessary to change the snapshot format in a way that messes with comparisons. Snapshots now record which capture format they used: format 1 for b26 and earlier and format 2 for b27. Comparing a format 1 snapshot against a format 2 snapshot shows a note explaining that some of the changes are the older snapshot recording the same settings in an older way, rather than anything on your Mac changing.

- **The built-in baselines are current** — The baselines a first snapshot is compared against have been recaptured on macOS 15.7.9 and macOS 26.6.2, so a first comparison no longer reports those same cross-version differences.

- **Privacy permissions are now tracked** — SetShot reports when an app gains or loses Full Disk Access, Media & Apple Music, camera, microphone, contacts, screen recording, accessibility, and around twenty other permissions, naming the app and the permission. This needs Full Disk Access for SetShot itself, made easier with a new button in Settings → Optional Data Sources, suggested by Chris Pepper.

- **Fixed: Music and TV settings stopped being captured after granting access** — Granting Media & Apple Music left capture switched off until you happened to open SetShot's Settings. It now follows the permission directly. There is also a button to reopen that pane once you have answered the prompt, which previously left no way back.

- **Security settings are now tracked** — System Integrity Protection, Gatekeeper, FileVault and the firewall were captured in every snapshot but recorded in a form SetShot could not read back, so they never appeared in a comparison — except the firewall, which appeared as two entries with garbled names instead of one change. All four report properly now, as do the time zone and the network time server, which suffered from the same problem.

- **Wallpaper and screen saver changes are now tracked** — Including per-display wallpapers, which is what you get when "Show on all Spaces" is turned off. Built-in wallpapers and aerials show their names — Sequoia Sunrise, Palau Jellies — instead of file paths or asset identifiers, displays are named the way System Settings names them, and placement reads Fill Screen or Center rather than a number.

- **Sound output and input devices are tracked** — macOS keeps no record on disk of which device sound plays through and records from — the audio preference files hold per-device settings, but nothing naming the active one — so connecting AirPods could switch every Sound setting on screen while a comparison reported nothing. Sound settings change whenever a device is connected or disconnected, not just when you choose one.

- **VPNs and other network connections are now tracked** — A VPN added by software — Tailscale, for instance — never showed up, because the network services SetShot read are the hardware ones and a VPN is not among them. Thanks to Brian Matthews for reporting this. Every service System Settings lists under Network → VPN is now reported by name, with its kind and whether it is switched on, so anything you didn't set up is visible. The kind is relevant because not everything listed there is a VPN.

- **More settings tracked** — The default Web browser and email client, launch agents and daemons, DNS servers, proxies and network services, Time Machine destinations, system extensions, configuration profiles, and whether the startup chime plays are now recorded.

- **Fixed: audio plug-ins produced tens of thousands of spurious changes** — On a Mac with Audio Unit plug-ins installed, macOS keeps a cache describing what each one can do, and rescanning the plug-ins renumbers the whole file. Mark Nagata's first comparison reported 33,000 changes, and all but a few thousand were that cache. None of those cache changes were settings, and now they're all ignored.

- **Fixed: energy settings looked like they changed when you unplugged** — On a laptop, every energy setting that differs between battery and the power adapter appeared to change the moment the power cord was unplugged. Both profiles are now captured separately and labeled "on battery" and "on the power adapter", so switching power sources changes nothing and each profile's setting is reported in its own right. The caveats added in b25 and b26 warning that these settings could look changed just from switching power sources are gone, along with the duplicate rows that reported the same energy setting twice. Desktop Macs, which have only one profile, no longer see the battery settings at all.

- **Fixed: one wallpaper change reported once per Space** — With "Show on all Spaces" turned on, macOS writes the same wallpaper into every Space, so changing it produced an identical "Wallpaper on Built-in Display" entry for each Space you had open. Spaces that recorded the same before and after now collapse to one entry per display; Spaces that genuinely held different wallpapers still report separately. Some of those entries also showed a raw key instead of a description, because the entry macOS writes as the default across Spaces has no Space identifier and the description could not read it.

- **Fixed: swapping an aerial for a photo read as two changes** — A wallpaper is stored either as an aerial's identifier or as a picture file, never both, so replacing one kind with the other reported the old one disappearing and the new one appearing as separate entries, each blank on one side. They now read as the one change they are — "Wallpaper on Studio Display: California State Route 58, Carrizo Plain, California → IMG_3115" — with the aerial named on the left.

- **Fixed: a Time Machine disk unmounting looked like a settings change** — Where a backup disk happens to be mounted is state, not a setting, but unplugging one reported the mount point vanishing and coming back. A destination actually being added or removed still shows.

- **Permission changes no longer bury a comparison** — Granting or revoking Full Disk Access or Media & Apple Music changes what SetShot can read, not what is set on your Mac. Revoking Full Disk Access used to report Time Machine as switched off and Mail's settings as wiped; turning off Media & Apple Music reported numerous Music and TV settings as deleted. SetShot now reports the permission change itself and says that anything appearing in only one snapshot reflects what it could read.

- **Clearer values throughout** — Trackpad click pressure, Full Keyboard Access, the dictation shortcut, notification sort order, the battery indicator and around twenty other settings show the names System Settings uses instead of raw numbers, and apps show their names instead of bundle identifiers. A setting that exists several times over — DNS servers, firewall entries, Time Machine destinations — now says which one of them a change is about rather than ending in a bare number.

- **macOS 27 betas are quieter** — A cache of game metadata, menu bar analytics, Spotlight evaluation counters and a handful of timestamps that macOS 27 rewrites on its own were turning up as changes in every comparison. They are ignored now. Full macOS 27 support will come after Apple officially releases it.

- **Fixed: the folder for new Finder windows showed the wrong value** — When set to a custom folder, both sides of a comparison showed today's folder rather than what each snapshot recorded, so changing from one custom folder to another reported nothing at all.

- **Fixed: a one-minute sleep timer read as "On"** — Setting a display or computer sleep timer to 1 minute showed the value as "On" rather than the number, because a setting whose zero means "Never" was still being treated as an on/off switch for its other values. Full Keyboard Access had the same problem with one of its modes.

- **Knowledge base updates** — Added around 130 new entries covering privacy permissions, security status, wallpaper, network configuration, and background items. Corrected mislabeled battery indicator values, the Notification Center sort order and Stage Manager grouping, the Lock Screen password hint, and menu bar clock and battery entries that showed no icon. Improved descriptions of the system font settings, Finder's Quit menu item, grammatical gender, the Spoken Content voice, the TV app appearance, and the Mail sender-domain list. Suppressed noise from analytics timestamps, transient Finder view settings, per-Space wallpaper duplication, and several daemon flags. Restructured the energy settings so each is recorded per power profile, and retired the duplicate entries that reported the same setting from a second source. Corrected the color filter values and the wallpaper scope labels. Added the Dock's Assign To, which records the desktop an app opens on, and Finder's sidebar visibility. Reworded the DNS server entry. Suppressed the Finder sidebar section states, the sidebar width, and two Mail keys that named a setting with no interface to reach it.

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
