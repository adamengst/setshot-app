import AppKit
import MusicKit
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var updaterState: UpdaterState
    @AppStorage("SUEnableAutomaticChecks") private var autoCheckForUpdates = true
    @AppStorage("OldestFirst") private var oldestFirst = false
    @AppStorage("AutoDeleteEmptyScheduledSnapshots") private var autoDeleteEmpty = true
    @AppStorage("CheckMusicSettings") private var checkMusicSettings = false
    @State private var isEnabled = SchedulerManager.isInstalled
    @State private var fdaGranted: Bool? = nil
    @State private var musicStatus: MusicAuthorization.Status? = nil
    @State private var scheduleUnit: ScheduleUnit = Self.loadedUnit()
    @State private var intervalCount: Int = Self.loadedIntervalCount()
    @State private var scheduleTime: Date = Self.loadedTime()
    @State private var scheduleWeekday: Int = Self.loadedWeekday()
    @State private var scheduleDay: Int = Self.loadedDay()
    @State private var errorMessage: String?

    private enum ScheduleUnit: String {
        case minutes, hours, day, week, month
        var isInterval: Bool { self == .minutes || self == .hours }
    }

    private static let intFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 1
        f.allowsFloats = false
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                schedulerSection
                dataSourcesSection
                displayOrderSection
                updatesSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(40)
        }
        .frame(maxWidth: .infinity)
        .task { await loadPermissionState() }
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

    private var updatesSection: some View {
        SettingsSection("Software Updates") {
            Toggle("Check for updates automatically", isOn: $autoCheckForUpdates)
                .onChange(of: autoCheckForUpdates) { newValue in
                    updaterState.controller.updater.automaticallyChecksForUpdates = newValue
                }
            Text("SetShot checks for new versions in the background once per hour. To check manually, choose SetShot \u{2192} Check for Updates.")
                .font(.caption)
                .foregroundStyle(.secondary)    
        }
    }

    private var dataSourcesSection: some View {
        SettingsSection("Optional Data Sources") {
            Text("SetShot can read two additional data sources when you have granted the necessary permissions. Neither is required, and both can be revoked at any time.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Music & Media Settings\(musicStatus.map { $0 == .authorized ? " (Enabled)" : " (Disabled)" } ?? "")")
                    .font(.system(size: 14))
                    .fontWeight(.medium)
                Text(musicDescription)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if musicStatus == .notDetermined {
                    Button("Request Media & Apple Music Access") {
                        requestMusicAccess()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("App Privacy Permissions\(fdaGranted.map { $0 ? " (Enabled)" : " (Disabled)" } ?? "")")
                    .font(.system(size: 14))
                    .fontWeight(.medium)
                Text(fdaDescription)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var fdaDescription: AttributedString {
        var str = AttributedString("For SetShot to detect which apps have been granted access to the microphone, camera, contacts, and similar resources, it needs Full Disk Access, which must be turned on manually. You can do so in ")
        var link = AttributedString("System Settings \u{2192} Privacy & Security \u{2192} Full Disk Access.")
        link.link = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        str += link
        return str
    }

    private var musicDescription: AttributedString {
        var str = AttributedString("For SetShot to read settings from the Music app, Home Sharing, and related systems, it needs Media & Apple Music access. When you enable this toggle, macOS will ask for permission on the next snapshot. You can review or revoke this in ")
        var link = AttributedString("System Settings \u{2192} Privacy & Security \u{2192} Media & Apple Music.")
        link.link = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Media")!
        str += link
        return str
    }

    private func loadPermissionState() async {
        async let fda = Task.detached(priority: .userInitiated) {
            SnapshotRunner.canReadSystemTCC()
        }.value
        async let music = Task.detached(priority: .userInitiated) {
            MusicAuthorization.currentStatus
        }.value
        fdaGranted = await fda
        let status = await music
        musicStatus = status
        // Sync UserDefaults with actual TCC state so the snapshot env var stays correct.
        // notDetermined also resets the flag — a tccutil reset must not leave
        // CheckMusicSettings=true while TCC is unsettled.
        if status == .authorized {
            checkMusicSettings = true
        } else {
            checkMusicSettings = false
        }
    }

    private func requestMusicAccess() {
        Task {
            let status = await MusicAuthorization.request()
            musicStatus = status
            checkMusicSettings = (status == .authorized)
        }
    }

    private var schedulerDescription: AttributedString {
        var str = AttributedString("SetShot installs a macOS LaunchAgent that runs on the chosen schedule, saving a snapshot without opening the app. If recognized changes are found, a notification appears that you can click to see the comparison. For notifications that stay on screen until clicked or dismissed, set SetShot's Alert Style to Persistent in ")
        var link = AttributedString("System Settings \u{2192} Notifications.")
        link.link = URL(string: "x-apple.systempreferences:com.apple.preference.notifications?com.tidbits.SetShot")!
        str += link
        return str
    }

    private var schedulerSection: some View {
        SettingsSection("Automatic Snapshots") {
            Text(schedulerDescription)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Take automatic snapshots", isOn: $isEnabled)
                .onChange(of: isEnabled) { enabled in
                    if enabled { requestNotificationPermission() }
                    toggleScheduler(enabled: enabled)
                }

            if isEnabled {
                scheduleControls
                    .padding(.leading, 20)
                Toggle("Delete scheduled snapshots with no changes", isOn: $autoDeleteEmpty)
                    .padding(.leading, 20)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var scheduleControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Every")

                if scheduleUnit.isInterval {
                    TextField("", value: $intervalCount, formatter: Self.intFormatter)
                        .frame(width: 44)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: intervalCount) { _ in toggleScheduler(enabled: true) }
                }

                Picker("", selection: $scheduleUnit) {
                    Section {
                        Text("minutes").tag(ScheduleUnit.minutes)
                        Text("hours").tag(ScheduleUnit.hours)
                    }
                    Section {
                        Text("day").tag(ScheduleUnit.day)
                        Text("week").tag(ScheduleUnit.week)
                        Text("month").tag(ScheduleUnit.month)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .onChange(of: scheduleUnit) { _ in toggleScheduler(enabled: true) }

                calendarSuffix()

                Spacer()
            }

            Text(nextRunDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func calendarSuffix() -> some View {
        switch scheduleUnit {
        case .day:
            HStack(spacing: 6) {
                Text("at")
                DatePicker("", selection: $scheduleTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .onChange(of: scheduleTime) { _ in toggleScheduler(enabled: true) }
            }
        case .week:
            HStack(spacing: 6) {
                Text("on")
                Picker("", selection: $scheduleWeekday) {
                    ForEach(1...7, id: \.self) { wd in Text(weekdayName(wd)).tag(wd) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .onChange(of: scheduleWeekday) { _ in toggleScheduler(enabled: true) }
                Text("at")
                DatePicker("", selection: $scheduleTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .onChange(of: scheduleTime) { _ in toggleScheduler(enabled: true) }
            }
        case .month:
            HStack(spacing: 6) {
                Text("on the")
                Picker("", selection: $scheduleDay) {
                    ForEach(1...31, id: \.self) { day in Text(ordinal(day)).tag(day) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .onChange(of: scheduleDay) { _ in toggleScheduler(enabled: true) }
                Text("at")
                DatePicker("", selection: $scheduleTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .onChange(of: scheduleTime) { _ in toggleScheduler(enabled: true) }
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Scheduler logic

    private func toggleScheduler(enabled: Bool) {
        do {
            if enabled {
                try SchedulerManager.install(schedule: buildSchedule())
            } else {
                try SchedulerManager.uninstall()
            }
            errorMessage = nil
        } catch {
            errorMessage = "Failed: \(error.localizedDescription)"
            isEnabled = !enabled
        }
    }

    private func buildSchedule() -> SnapshotSchedule {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: scheduleTime)
        let hour = comps.hour ?? 8
        let minute = comps.minute ?? 0
        switch scheduleUnit {
        case .minutes: return .interval(minutes: max(1, intervalCount))
        case .hours:   return .interval(minutes: max(1, intervalCount) * 60)
        case .day:     return .daily(hour: hour, minute: minute)
        case .week:    return .weekly(weekday: scheduleWeekday, hour: hour, minute: minute)
        case .month:   return .monthly(day: scheduleDay, hour: hour, minute: minute)
        }
    }

    private func requestNotificationPermission() {
        Task {
            try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
        }
    }

    // MARK: - Next run description

    private var nextRunDescription: String {
        guard let next = computeNextRun() else { return "" }
        return "Next run: \(formatNextRun(next))"
    }

    private func computeNextRun() -> Date? {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: scheduleTime)
        switch scheduleUnit {
        case .minutes:
            return Date.now.addingTimeInterval(Double(intervalCount * 60))
        case .hours:
            return Date.now.addingTimeInterval(Double(intervalCount * 3600))
        case .day:
            return cal.nextDate(after: .now,
                matching: DateComponents(hour: t.hour, minute: t.minute, second: 0),
                matchingPolicy: .nextTime)
        case .week:
            return cal.nextDate(after: .now,
                matching: DateComponents(hour: t.hour, minute: t.minute, second: 0, weekday: scheduleWeekday),
                matchingPolicy: .nextTime)
        case .month:
            return cal.nextDate(after: .now,
                matching: DateComponents(day: scheduleDay, hour: t.hour, minute: t.minute, second: 0),
                matchingPolicy: .nextTime)
        }
    }

    private func formatNextRun(_ date: Date) -> String {
        let cal = Calendar.current
        let tf = DateFormatter()
        tf.timeStyle = .short
        let timeStr = tf.string(from: date)
        if cal.isDateInToday(date) {
            return "today at \(timeStr)"
        } else if cal.isDateInTomorrow(date) {
            return "tomorrow at \(timeStr)"
        } else {
            let df = DateFormatter()
            df.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
            return "\(df.string(from: date)) at \(timeStr)"
        }
    }

    // MARK: - Helpers

    private func weekdayName(_ weekday: Int) -> String {
        DateFormatter().weekdaySymbols[max(0, weekday - 1)]
    }

    private func ordinal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    // MARK: - Initial state loading

    private static func loadedUnit() -> ScheduleUnit {
        switch SchedulerManager.installedSchedule() {
        case .interval(let m) where m < 60: return .minutes
        case .interval:                     return .hours
        case .daily:                        return .day
        case .weekly:                       return .week
        case .monthly:                      return .month
        case nil:                           return .day
        }
    }

    private static func loadedIntervalCount() -> Int {
        switch SchedulerManager.installedSchedule() {
        case .interval(let m) where m < 60: return m
        case .interval(let m):              return m / 60
        default:                            return 24
        }
    }

    private static func loadedTime() -> Date {
        let hour: Int
        let minute: Int
        switch SchedulerManager.installedSchedule() {
        case .daily(let h, let m):
            hour = h; minute = m
        case .weekly(_, let h, let m):
            hour = h; minute = m
        case .monthly(_, let h, let m):
            hour = h; minute = m
        default:
            hour = 8; minute = 0
        }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? .now
    }

    private static func loadedWeekday() -> Int {
        if case .weekly(let wd, _, _) = SchedulerManager.installedSchedule() { return wd }
        return 2
    }

    private static func loadedDay() -> Int {
        if case .monthly(let d, _, _) = SchedulerManager.installedSchedule() { return d }
        return 1
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
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(.leading, 12)
        }
    }
}
