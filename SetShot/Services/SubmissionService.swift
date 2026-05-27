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
        for chunk in Self.chunked(items, size: 150) {
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

    private func post<T: Encodable>(_ body: T) async throws {
        var request = URLRequest(url: workerURL)
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
