import Foundation

actor SubmissionService {
    static let shared = SubmissionService()

    private let workerURL = URL(string: "https://setshot-submission.the-account-of-adam-engst.workers.dev")!

    func submit(_ diff: DiffLine) async throws {
        var request = URLRequest(url: workerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "domain": diff.domain,
            "key": diff.key,
            "source": diff.source,
            "before_value": diff.beforeValue,
            "after_value": diff.afterValue,
            "macos_version": diff.macOSVersion
        ]
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
