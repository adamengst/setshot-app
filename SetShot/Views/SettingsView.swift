import SwiftUI

struct SettingsView: View {
    @AppStorage("OldestFirst") private var oldestFirst = false
    @State private var isEnabled = SchedulerManager.isInstalled
    @State private var scheduleTime = SchedulerManager.installedTime() ?? defaultTime()
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                displayOrderSection
                schedulerSection
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sections

    private var displayOrderSection: some View {
        SettingsSection("Display Order") {
            Toggle("Show oldest first", isOn: $oldestFirst)
            Text("Applies to both the Snapshots list and the Journal.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var schedulerSection: some View {
        SettingsSection("Daily Automatic Snapshot") {
            Text("SetShot installs a macOS LaunchAgent that runs at the scheduled time, saving a snapshot without opening the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                Toggle("Take a daily snapshot at", isOn: $isEnabled)
                    .onChange(of: isEnabled) { enabled in
                        toggleScheduler(enabled: enabled)
                    }
                if isEnabled {
                    DatePicker("", selection: $scheduleTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(maxWidth: 90)
                        .onChange(of: scheduleTime) { _ in
                            if isEnabled { toggleScheduler(enabled: true) }
                        }
                }
            }

            if isEnabled {
                Text(nextRunDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Scheduler logic

    private func toggleScheduler(enabled: Bool) {
        do {
            if enabled {
                let comps = Calendar.current.dateComponents([.hour, .minute], from: scheduleTime)
                try SchedulerManager.install(hour: comps.hour ?? 8, minute: comps.minute ?? 0)
            } else {
                try SchedulerManager.uninstall()
            }
            errorMessage = nil
        } catch {
            errorMessage = "Failed: \(error.localizedDescription)"
            isEnabled = !enabled
        }
    }

    private var nextRunDescription: String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: scheduleTime)
        var todayComps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        todayComps.hour = comps.hour ?? 8
        todayComps.minute = comps.minute ?? 0
        todayComps.second = 0
        guard let todayRun = Calendar.current.date(from: todayComps) else { return "" }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeStr = formatter.string(from: todayRun)
        return todayRun > .now ? "Next run: today at \(timeStr)" : "Next run: tomorrow at \(timeStr)"
    }

    private static func defaultTime() -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        comps.hour = 8
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? .now
    }
}

// MARK: - Layout helper

private struct SettingsSection<Content: View>: View {
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
