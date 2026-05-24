import SwiftUI

struct SchedulerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isEnabled = SchedulerManager.isInstalled
    @State private var scheduleTime = SchedulerManager.installedTime() ?? defaultTime()
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Settings").font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text("Daily Automatic Snapshot").font(.headline)
                Text("SetShot installs a macOS LaunchAgent that runs your bundled setshot.sh script at the scheduled time, saving a snapshot without opening the app.")
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
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420, height: 220)
    }

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

        if todayRun > .now {
            return "Next run: today at \(timeStr)"
        } else {
            return "Next run: tomorrow at \(timeStr)"
        }
    }

    private static func defaultTime() -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        comps.hour = 8
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? .now
    }
}
