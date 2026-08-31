import Foundation

/// Runs a `Process` so that cancelling the surrounding Task terminates the child.
///
/// `Process` has no async interface, so every call site wraps it in a continuation.
/// A bare continuation ignores cancellation entirely: the child keeps running and
/// the `await` never returns, so cancelling a capture left the spinner turning
/// until the script finished on its own. Terminating from the cancellation handler
/// is what actually stops the work.
enum CancellableProcess {

    /// Guards the one-shot resume. `terminationHandler` and the cancellation handler
    /// run on different threads, and a continuation must be resumed exactly once.
    private final class State {
        private let lock = NSLock()
        private var process: Process?
        private var finished = false
        private var cancelled = false

        /// Records the process and starts it, or throws if cancellation already won.
        func start(_ process: Process) throws {
            lock.lock()
            if cancelled {
                lock.unlock()
                throw CancellationError()
            }
            self.process = process
            lock.unlock()
            try process.run()
        }

        /// nil when the completion was already claimed; otherwise whether the run
        /// was cancelled, so the caller knows which way to resume.
        func claim() -> Bool? {
            lock.lock()
            defer { lock.unlock() }
            if finished { return nil }
            finished = true
            return cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let running = process
            lock.unlock()
            // A process that never launched has nothing to terminate; `start` sees
            // the flag instead and throws.
            if let running, running.isRunning { running.terminate() }
        }
    }

    /// Runs `process` to completion and maps the finished process to a value.
    /// Throws `CancellationError` if the Task is cancelled, having terminated the child.
    static func run<T>(_ process: Process, whenDone: @escaping (Process) -> T) async throws -> T {
        let state = State()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                process.terminationHandler = { finished in
                    guard let cancelled = state.claim() else { return }
                    if cancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(returning: whenDone(finished))
                    }
                }
                do {
                    try state.start(process)
                } catch {
                    guard state.claim() != nil else { return }
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            state.cancel()
        }
    }
}
