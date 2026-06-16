import SwiftUI

struct AboutView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                intro
                setShotViews
                takingSnapshots
                comparingSnapshots
                understandingResults
                theJournal
                submittingChanges
                improvingRecognized
                automaticSnapshots
                permissions
                privacy
            }
            .font(.system(size: 14))
            .padding(40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About SetShot")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Have you ever thought a macOS update changed some setting silently? Or have you spelunked through System Settings and wondered later what you clicked? With SetShot, you can find out what settings have changed over time, making it easy to see what you've done and revert inadvertent changes.")
                .fixedSize(horizontal: false, vertical: true)
            Text("SetShot lets you capture a complete snapshot of your Mac's settings at any point in time so you can compare any two snapshots and see exactly what changed, in plain English. Each recognized change comes with a description, its location in System Settings, and — where possible — a button that opens the exact pane directly.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissions: some View {
        HelpSection("Optional Permissions") {
            HelpParagraph("By default, SetShot takes snapshots without requesting any special permissions. Two optional data sources in **Settings → Optional Data Sources** expand what SetShot captures:")

            HelpCallout("Music App Settings") {
                Text("When enabled, SetShot reads Music, Home Sharing, and related preferences. macOS will display a **Media & Apple Music** permission dialog the first time a snapshot runs — click **Allow**. This permission is remembered permanently.")
            }
            screenshot("PermissionMusicAccess")

            HelpCallout("App Privacy Permissions") {
                Text("When enabled, SetShot reads the system privacy database to detect which apps have been granted access to the microphone, camera, contacts, and similar resources. This requires **Full Disk Access** — grant it in **System Settings → Privacy & Security → Full Disk Access**, or use the button in Settings → Optional Data Sources.")
            }

            HelpParagraph("One more permission is used when automatic snapshots are enabled:")

            HelpCallout("Notifications") {
                Text("When you enable automatic snapshots in Settings, macOS will ask for Notifications permission. If granted, a notification appears whenever a scheduled snapshot finds recognized changes; clicking it opens the comparison.")
            }
        }
    }

    @ViewBuilder
    private func screenshot(_ name: String) -> some View {
        if let nsImage = NSImage(named: name) {
            Image(nsImage: nsImage)
                .resizable()
                .frame(width: nsImage.size.width / 2, height: nsImage.size.height / 2)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
    }

    private var setShotViews: some View {
        HelpSection("SetShot Views") {
            HelpParagraph("SetShot has four views, accessed by clicking the buttons at the top of the window:")
            screenshot("ScreenshotNavigation")
            VStack(alignment: .leading, spacing: 6) {
                HelpBullet("**Snapshots:** Shows all the snapshots you've taken in Before and After columns.")
                HelpBullet("**Journal:** A chronological log of all recognized changes across your comparisons.")
                HelpBullet("**Settings:** Reverse sort order and set up automatic daily snapshots.")
                HelpBullet("**About:** You're reading it now.")
            }
        }
    }

    private var takingSnapshots: some View {
        HelpSection("Taking Snapshots") {
            HelpParagraph("SetShot's core function is to take and compare snapshots. To that end, it scans nearly 500 settings files across more than a dozen system data sources. It currently recognizes over 400 settings and knows to ignore over 50 additional changes that are just macOS noise.")
            HelpParagraph("To take a snapshot of the current state of your Mac's settings, click **Take Snapshot** at the bottom of the Snapshots view. SetShot saves the result to the snapshot library with the date and time. Snapshots are stored in `~/Library/Application Support/SetShot/snapshots` as gzipped files that occupy little space. Capturing typically takes less than a minute.")
            screenshot("ScreenshotSnapshotsContext")
            HelpParagraph("Each snapshot line shows the number of recognized changes from the previous snapshot and the size of the snapshot file.")
            HelpParagraph("To rename a snapshot, Control-click it and choose **Rename**, then type a new name. Renaming can be useful for labelling snapshots with context — for example, “Before macOS 26.6” or “After Accessibility testing.”")
            HelpParagraph("To remove an unnecessary snapshot, Control-click it and choose **Delete**.")
        }
    }

    private var comparingSnapshots: some View {
        HelpSection("Comparing Snapshots") {
            HelpParagraph("Once you've taken at least two snapshots, you can use SetShot to compare them.")
            HelpParagraph("The Snapshots view shows two columns. Click a snapshot in the left column to set it as the **Before** snapshot, and click a snapshot in the right column to set it as the **After** snapshot.")
            screenshot("ScreenshotSnapshotsReady")
            HelpParagraph("Once you have selected both snapshots, click **Compare** to run the comparison. The results open in a new window titled with the names of the two snapshots, leaving the snapshot library available so you can start additional comparisons. You can have multiple comparison windows open at once to look at them side by side.")
            HelpParagraph("SetShot identifies every setting that differs between the two snapshots and looks up each one in its knowledge base to determine whether it's a recognized change or an unrecognized change. Changes to the knowledge base are read at every launch.")
        }
    }

    private var understandingResults: some View {
        HelpSection("Understanding Results") {
            HelpParagraph("Results are divided into two sections:")

            HelpCallout("Recognized Changes") {
                Text("Settings already in SetShot's knowledge base. Each entry shows a plain-English description, the path to find it in System Settings, and — where possible — an **Open in Settings** button that takes you directly to the relevant pane. The old value appears in orange and the new value in blue. A **Submit Feedback** button lets you flag issues with the description, path, icon, or value formatting to help improve SetShot for everyone.")
            }

            HelpCallout("Unrecognized Changes") {
                Text("Changes that are either noise or legitimate settings changes that aren't yet in the knowledge base. The raw technical name of the setting is shown along with its old and new values. You can submit these to help improve SetShot for everyone.")
            }

            HelpParagraph("Values are displayed in a readable form where possible: toggles show On or Off, volume settings show a percentage, file paths show just the filename, and settings with a fixed list of options (like Hot Corner actions) show the option name rather than a raw number.")
            screenshot("ScreenshotResults")
        }
    }

    private var submittingChanges: some View {
        HelpSection("Submitting Unrecognized Changes") {
            HelpParagraph("When you find an unrecognized change that is either noise or that you think should be included in the knowledge base, click **Submit** on that row. A confirmation sheet shows exactly what data will be sent — the internal setting name, its old and new values, and your macOS version — and nothing else.")
            HelpParagraph("The sheet also offers an optional feedback section. If you have a sense of what the change represents, select one of the two categories:")

            HelpCallout("Expected settings change") {
                Text("The change reflects something real — a preference you set, a feature you turned on, or a setting macOS adjusted as a result of something you did.")
            }

            HelpCallout("Likely macOS noise") {
                Text("The change appears to be an internal macOS value that fluctuates on its own, unrelated to any setting you'd want to track.")
            }

            HelpParagraph("You can also add a short note with any context that might help with review. Both fields are entirely optional, but adding context may help categorize the change more accurately.")
            screenshot("ScreenshotSubmitUnrecognized")
            HelpParagraph("If you have several unrecognized changes, click **Submit All** to review and send them all at once. Submitted changes are reviewed, added to the knowledge base, and loaded on the next launch, making SetShot more useful for everyone.")
            HelpParagraph("Already-submitted rows are marked with a checkmark for the duration of the session.")
        }
    }

    private var improvingRecognized: some View {
        HelpSection("Improving Recognized Changes") {
            HelpParagraph("Even recognized changes can have room for improvement: an icon may be missing, a description may be unclear, a System Settings path may be wrong, or values may show as raw numbers instead of readable labels.")
            HelpParagraph("Click **Submit Feedback** on any recognized change row to open a feedback sheet. Check the issues that apply, add any notes that might help, and click **Submit**. The sheet shows a summary of the current description and location so you can refer to them while writing.")
            screenshot("ScreenshotSubmitRecognized")
            HelpParagraph("Feedback is reviewed by the developer and incorporated into future knowledge base updates, making SetShot more accurate for everyone.")
        }
    }

    private var privacy: some View {
        HelpSection("Privacy") {
            HelpParagraph("The data SetShot works with is inherently non-sensitive — it's system settings like toggles, sliders, and preferences, not passwords, documents, photos, or personal content. That said, SetShot is designed to keep your data private.")
            HelpBullet("**Snapshots, comparisons, and journal entries** are stored only on this Mac and are never transmitted anywhere.")
            HelpBullet("**Submissions** are the one exception. When you submit an unrecognized change or send feedback on a recognized change, the relevant setting data is sent to the developer over a secure connection and stored privately. Submissions are entirely opt-in. As with any Internet connection, your IP address is seen by the service that handles submissions (Cloudflare) but is not stored in your submission record.")
            HelpParagraph("SetShot is open source. If you want to verify exactly what data the app collects and how it is handled, the full source code is available at [github.com/adamengst/setshot-app](https://github.com/adamengst/setshot-app).")
        }
    }

    private var automaticSnapshots: some View {
        HelpSection("Automatic Snapshots") {
            HelpParagraph("SetShot can take snapshots automatically on a schedule. Click **Settings** in the segmented control at the top, then select **Take automatic snapshots** and choose how often: every N minutes, every N hours, once a day, once a week, or once a month. For day, week, and month intervals, you can also set the time of day.")
            HelpParagraph("Automatic snapshots are taken silently in the background without SetShot's window appearing. This lets you build up a history of your Mac's settings over time without having to remember to capture manually.")
            HelpParagraph("When you enable automatic snapshots, macOS will ask for **Notifications** permission. If granted, a notification appears whenever a scheduled snapshot finds recognized changes; clicking it opens the comparison in SetShot.")
            HelpParagraph("Enable **Delete scheduled snapshots with no changes** to automatically remove snapshots taken by the scheduler that found no changes, keeping your library uncluttered.")
            screenshot("ScreenshotSettings")
        }
    }

    private var theJournal: some View {
        HelpSection("The Journal") {
            HelpParagraph("The journal keeps a cumulative record of every recognized change found across all your comparisons. Switch to it by clicking **Journal** in the segmented control at the top of the SetShot window.")
            HelpParagraph("Journal entries are grouped by comparison, with a header showing the date and time of the comparison and how many recognized changes it found. Each entry shows the setting description, its location in System Settings, and the before and after values. An **Open in Settings** button appears when possible.")
            HelpParagraph("Use the search field at the top to filter entries by description, setting name, or location. Control-click an entry to delete it, or Control-click a section header to remove all entries from that comparison at once. To wipe the entire journal, click **Clear All** to the right of the search fieldyou'll be asked to confirm first.")
            HelpParagraph("The journal automatically eliminates redundant entries: if the same change appears more than once — for instance, if you run the same comparison twice — only the earliest occurrence is kept.")
            screenshot("ScreenshotJournal")
        }
    }

}

// MARK: - Layout helpers

struct HelpSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            content
        }
    }
}

struct HelpParagraph: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct HelpBullet: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct HelpCallout<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .fontWeight(.medium)
            content
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }
}
