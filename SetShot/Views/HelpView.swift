import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                overview
                takingSnapshots
                comparingSnapshots
                understandingResults
                submittingChanges
                automaticSnapshots
            }
            .padding(40)
        }
        .frame(width: 620)
    }

    // MARK: - Sections

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SetShot Help")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("SetShot captures a complete snapshot of your Mac's settings, then lets you compare two snapshots to show you exactly what changed — and what each change means. It's designed for situations where you want to see what changes are made after applying a macOS update or tweaking options in System Settings.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var takingSnapshots: some View {
        HelpSection("Taking Snapshots") {
            HelpParagraph("Click **Take Snapshot** in the toolbar to capture the current state of your Mac's settings. SetShot reads preferences, system configuration, and other state sources, then saves the result to the snapshot library with the date and time.")
            HelpParagraph("The snapshot captures hundreds of settings across System Settings, accessibility options, network configuration, default app handlers, and more. Capturing typically takes a few seconds.")
            HelpParagraph("To rename a snapshot, Control-click it and choose **Rename**, then type a new name or click to position the insertion point. This is useful for labelling snapshots with context — for example, **Before software install** or **After update**.")
            HelpParagraph("To remove an unnecessary snapshot, Control-click it and choose **Delete**")
        }
    }

    private var comparingSnapshots: some View {
        HelpSection("Comparing Snapshots") {
            HelpParagraph("The library shows two columns. Click a snapshot in the left column to set it as the **Before** snapshot, and click a snapshot in the right column to set it as the **After** snapshot. The Before snapshot should be the earlier one.")
            HelpParagraph("Once you have selected both snapshots, click **Compare** to run the comparison. SetShot identifies every setting that differs between the two snapshots and looks up each one in its knowledge base to determine whether it's a recognized change, an unrecognized change, or background noise.")
        }
    }

    private var understandingResults: some View {
        HelpSection("Understanding Results") {
            HelpParagraph("Results are divided into three sections:")

            HelpCallout("Recognized Changes") {
                Text("Settings that SetShot's knowledge base knows about. Each entry shows a plain-English description, the path to find it in System Settings, and — where possible — an **Open in Settings** button that takes you directly to the relevant pane. The old value appears in orange and the new value in blue.")
            }

            HelpCallout("Unrecognized Changes") {
                Text("Changes that are either noise or legitimate settings changes that aren't yet in the knowledge base. The raw technical name of the setting is shown along with its old and new values. You can submit these to help improve SetShot for everyone.")
            }

            HelpParagraph("Values are displayed in a readable form where possible: toggles show On or Off, volume settings show a percentage, file paths show just the filename, and settings with a fixed list of options (like Hot Corner actions) show the option name rather than a raw number. If you see a value that's not readable, send me a screenshot.")
        }
    }

    private var submittingChanges: some View {
        HelpSection("Submitting Unrecognized Changes") {
            HelpParagraph("When you find an unrecognized change that is either noise or that you think should be included in the knowledge base, click **Submit** on that row. A confirmation sheet shows exactly what data will be sent — the internal setting name, its old and new values, and your macOS version — and nothing else.")
            HelpParagraph("If you have several unrecognized changes, click **Submit All** to send them all at once. Submitted changes are reviewed and added to the knowledge base, making SetShot more useful for everyone.")
            HelpParagraph("Already-submitted rows are marked with a checkmark for the duration of the session.")
        }
    }

    private var automaticSnapshots: some View {
        HelpSection("Automatic Snapshots") {
            HelpParagraph("SetShot can take snapshots automatically on a schedule. Click the gear icon in the library toolbar to open the scheduler settings.")
            HelpParagraph("Automatic snapshots are taken silently in the background without SetShot's window appearing, and are labelled **Automatic** in the library. This lets you build up a history of your Mac's settings over time without having to remember to capture manually.")
        }
    }

}

// MARK: - Layout helpers

private struct HelpSection<Content: View>: View {
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

private struct HelpParagraph: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct HelpCallout<Content: View>: View {
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
