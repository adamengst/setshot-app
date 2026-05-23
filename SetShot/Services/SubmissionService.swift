import Foundation

actor SubmissionService {
    static let shared = SubmissionService()

    private let workerURL = URL(string: "https://setshot-submission.the-account-of-adam-engst.workers.dev")!

    func submit(_ diff: DiffLine) async throws {
        // TODO: implemented in SubmissionService session
    }
}
