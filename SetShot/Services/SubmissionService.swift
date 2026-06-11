import Foundation

enum FeedbackCategory: String {
    case expectedChange = "expected_change"
    case likelyNoise = "likely_noise"
}

struct UserFeedback {
    let category: FeedbackCategory?
    let notes: String
}

actor SubmissionService {
    static let shared = SubmissionService()

    private let workerURL = URL(string: "https://setshot-submission.the-account-of-adam-engst.workers.dev")!

    func submit(_ diff: DiffLine, feedback: UserFeedback? = nil) async throws {
        try await post(payload(for: diff, feedback: feedback))
    }

    func submitBatch(_ diffs: [DiffLine]) async throws {
        let items = diffs.map { payload(for: $0) }
        for chunk in Self.chunked(items, size: 40) {
            try await post(chunk)
        }
    }

    static func chunked<T>(_ items: [T], size: Int) -> [[T]] {
        stride(from: 0, to: items.count, by: size).map {
            Array(items[$0 ..< min($0 + size, items.count)])
        }
    }

    private func payload(for diff: DiffLine, feedback: UserFeedback? = nil) -> [String: String] {
        var p: [String: String] = [
            "domain": diff.domain,
            "key": diff.key,
            "source": diff.source,
            "before_value": diff.beforeValue.isEmpty ? "(not set)" : diff.beforeValue,
            "after_value": diff.afterValue.isEmpty ? "(not set)" : diff.afterValue,
            "macos_version": diff.macOSVersion
        ]
        if let fb = feedback {
            if let cat = fb.category { p["feedback_category"] = cat.rawValue }
            let notes = fb.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty { p["feedback_notes"] = notes }
        }
        return p
    }

    func submitKBFeedback(entry: KBEntry, diff: DiffLine,
                          issues: [KBFeedbackIssue], notes: String) async throws {
        var payload: [String: String] = [
            "entry_id":               entry.id,
            "domain":                 entry.domain,
            "key":                    entry.key,
            "current_description":    entry.description ?? "",
            "current_ui_location":    entry.uiLocation ?? "",
            "current_settings_url":   entry.settingsURL ?? "",
            "current_icon_bundle_id": entry.iconBundleID ?? "",
            "macos_version":          diff.macOSVersion,
            "issues":                 issues.map(\.rawValue).joined(separator: ",")
        ]
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { payload["notes"] = trimmed }
        try await post(payload, path: "/kb-feedback")
    }

    private func post<T: Encodable>(_ body: T, path: String = "") async throws {
        let url = path.isEmpty ? workerURL : workerURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SubmissionError.serverError
        }
    }
}

enum SubmissionError: LocalizedError {
    case serverError

    var errorDescription: String? {
        "Submission failed. Please try again."
    }
}
