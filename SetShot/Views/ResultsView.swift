import SwiftUI

struct ResultsView: View {
    let diff: DiffResult
    let before: StoredSnapshot
    let after: StoredSnapshot
    @State private var submittedIDs: Set<UUID> = []
    @State private var isSubmittingAll = false
    @State private var showSubmitAllPreview = false
    @State private var submitError: String? = nil
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                recognizedSection
                unrecognizedSection
            }
            .padding(32)
            .background(GeometryReader { geo in
                Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
            })
        }
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .navigationTitle("\(before.displayName) → \(after.displayName)")
        .background(ComparisonWindowPositioner(contentHeight: contentHeight))
        .sheet(isPresented: $showSubmitAllPreview) {
            let unsubmitted = diff.unrecognized.filter { !submittedIDs.contains($0.id) }
            SubmitAllPreviewView(
                items: unsubmitted,
                isPresented: $showSubmitAllPreview,
                onSubmit: { submitAll(unsubmitted) }
            )
        }
        .alert("Submission Failed", isPresented: Binding(
            get: { submitError != nil },
            set: { if !$0 { submitError = nil } }
        )) {
            Button("OK") { submitError = nil }
        } message: {
            Text(submitError ?? "")
        }
        .frame(minWidth: 600)
    }

    private var recognizedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Recognized Changes", count: diff.recognized.count)
            if diff.recognized.isEmpty {
                Text("No recognized changes.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(diff.recognized, id: \.diff.id) { item in
                    RecognizedRow(entry: item.entry, diff: item.diff)
                }
            }
        }
    }

    private var unrecognizedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("Unrecognized Changes", count: diff.unrecognized.count + diff.unrecognizedOverflow)
                Spacer()
                submitAllButton
            }
            if diff.unrecognized.isEmpty {
                Text("All changes were identified.")
                    .foregroundStyle(.secondary)
            } else {
                if diff.unrecognizedOverflow > 0 {
                    Text("\(diff.unrecognized.count) of \(diff.unrecognized.count + diff.unrecognizedOverflow) unrecognized changes shown. The remaining \(diff.unrecognizedOverflow) are likely from a snapshot taken before a SetShot update changed what is captured — retake your baseline snapshot to clear them.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(diff.unrecognized) { line in
                    UnrecognizedRow(
                        diff: line,
                        isSubmitted: submittedIDs.contains(line.id),
                        onMarkSubmitted: { submittedIDs.insert(line.id) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var submitAllButton: some View {
        let unsubmitted = diff.unrecognized.filter { !submittedIDs.contains($0.id) }
        if !unsubmitted.isEmpty {
            if isSubmittingAll {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Submitting…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Submit All (\(unsubmitted.count))") {
                    showSubmitAllPreview = true
                }
                .controlSize(.small)
            }
        }
    }

    private func submitAll(_ items: [DiffLine]) {
        isSubmittingAll = true
        submitError = nil
        Task {
            do {
                try await SubmissionService.shared.submitBatch(items)
                for item in items { submittedIDs.insert(item.id) }
            } catch {
                submitError = error.localizedDescription
            }
            isSubmittingAll = false
        }
    }

}

func formatValue(_ raw: String, key: String = "", valueMap: [String: String]? = nil) -> String {
    if let map = valueMap {
        // Normalize True/False → 1/0 for value_map lookup since FLATTEN_PY
        // converts integer 0/1 to booleans, but value_map keys use integers.
        let lookupKey = raw == "True" ? "1" : raw == "False" ? "0" : raw
        if let label = map[lookupKey] { return label }
    }
    switch raw.lowercased() {
    case "true", "yes", "1": return "On"
    case "false", "no", "0": return "Off"
    default: break
    }
    if raw.hasPrefix("/"), let url = URL(string: "file://\(raw)") {
        return url.deletingPathExtension().lastPathComponent
    }
    if key.localizedCaseInsensitiveContains("volume"), let f = Double(raw) {
        return "\(Int((f * 100).rounded()))%"
    }
    return raw
}

private struct SectionHeader: View {
    let title: String
    let count: Int

    init(_ title: String, count: Int) {
        self.title = title
        self.count = count
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.headline)
            Text("(\(count))").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private struct RecognizedRow: View {
    let entry: KBEntry
    let diff: DiffLine

    private static let macOSMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

    var body: some View {
        let settingsURL = validatedSettingsURL(entry.settingsURL)
        let uiLocation = entry.effectiveUILocation(macOSMajor: Self.macOSMajor)

        HStack(alignment: .top, spacing: 12) {
            SettingsPaneIcon(settingsURL: entry.settingsURL, domain: diff.domain, iconBundleID: entry.iconBundleID)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.description ?? "")
                            .fontWeight(.medium)
                        if let location = uiLocation {
                            Text(location)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let url = settingsURL {
                        Button("Open in Settings") {
                            NSWorkspace.shared.open(url)
                        }
                        .controlSize(.small)
                    }
                }
                HStack(spacing: 6) {
                    Text(diff.beforeValue.isEmpty ? "(none)" : formatValue(diff.beforeValue, key: diff.key, valueMap: entry.valueMap))
                        .foregroundStyle(.orange)
                    Text("→")
                        .foregroundStyle(.secondary)
                    Text(diff.afterValue.isEmpty ? "(none)" : formatValue(diff.afterValue, key: diff.key, valueMap: entry.valueMap))
                        .foregroundStyle(.blue)
                }
                .font(.system(.callout, design: .monospaced))
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private func validatedSettingsURL(_ raw: String?) -> URL? {
        guard let raw,
              raw.hasPrefix("x-apple.systempreferences:"),
              !raw.contains("://"),
              !raw.contains(" ") else { return nil }
        return URL(string: raw)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ComparisonWindowPositioner: NSViewRepresentable {
    let contentHeight: CGFloat

    func makeNSView(context: Context) -> PositionerView { PositionerView() }
    func updateNSView(_ nsView: PositionerView, context: Context) {
        nsView.contentHeight = contentHeight
        nsView.applyWhenReady()
    }

    class PositionerView: NSView {
        private static var nextCascadePoint: NSPoint? = nil
        var contentHeight: CGFloat = 0
        private var windowReady = false
        private var done = false
        private var closeObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !windowReady else { return }
            windowReady = true
            window.alphaValue = 0

            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                let remaining = NSApp.windows.filter { $0.title.contains("→") && $0.isVisible }
                if remaining.count <= 1 { Self.nextCascadePoint = nil }
                if let obs = self?.closeObserver { NotificationCenter.default.removeObserver(obs) }
                self?.closeObserver = nil
            }

            applyWhenReady()
        }

        func applyWhenReady() {
            guard !done, windowReady, contentHeight > 0, let window else { return }
            done = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak window] in
                guard let self, let window else { return }

                guard let main = NSApp.windows.first(where: {
                    $0 !== window && $0.isVisible && !$0.isMiniaturized && $0.title == "SetShot"
                }) else { return }

                // Position first — after this, window.screen reflects the destination display.
                let startPoint = Self.nextCascadePoint ?? NSPoint(x: main.frame.maxX + 8, y: main.frame.maxY)
                Self.nextCascadePoint = window.cascadeTopLeft(from: startPoint)

                let titleBarHeight = window.frame.height - (window.contentView?.bounds.height ?? window.frame.height)

                if let screen = window.screen ?? NSScreen.main {
                    let sf = screen.visibleFrame
                    var f = window.frame

                    // Clamp right edge within screen.
                    if f.maxX > sf.maxX { f.origin.x = sf.maxX - f.width }

                    // Cap height to the space available from the window's top edge
                    // down to the screen bottom — not the full screen height, so
                    // cascaded windows that start lower don't extend off-screen.
                    let availableH = f.maxY - sf.minY
                    let targetContentH = min(self.contentHeight + 24, max(0, availableH - titleBarHeight))
                    let newH = targetContentH + titleBarHeight
                    f.origin.y = f.maxY - newH  // keep top edge fixed
                    f.size.height = newH
                    window.setFrame(f, display: false, animate: false)
                }

                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    window.animator().alphaValue = 1
                }
            }
        }

        deinit {
            if let obs = closeObserver { NotificationCenter.default.removeObserver(obs) }
        }
    }
}

private struct UnrecognizedRow: View {
    let diff: DiffLine
    let isSubmitted: Bool
    let onMarkSubmitted: () -> Void
    @State private var showSheet = false

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(diff.rawLine)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(diff.beforeValue.isEmpty ? "(none)" : formatValue(diff.beforeValue, key: diff.key))
                        .foregroundStyle(.orange)
                    Text("→")
                        .foregroundStyle(.secondary)
                    Text(diff.afterValue.isEmpty ? "(none)" : formatValue(diff.afterValue, key: diff.key))
                        .foregroundStyle(.blue)
                }
                .font(.system(.callout, design: .monospaced))
            }
            Spacer()
            if isSubmitted {
                Label("Submitted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                Button("Submit") { showSheet = true }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
        .sheet(isPresented: $showSheet) {
            SubmitView(diff: diff, isPresented: $showSheet, onSubmitted: onMarkSubmitted)
        }
    }
}

