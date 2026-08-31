import Foundation

/// Whether macOS is running SetShot from a randomised read-only copy of itself.
///
/// Gatekeeper translocates an app that still carries the quarantine flag and is
/// opened from where it was unzipped rather than moved to Applications. Instead of
/// running the app where it sits, macOS mounts a copy at
/// `/private/var/folders/…/AppTranslocation/<uuid>/d/SetShot.app` and runs that.
/// The location differs on every launch and does not outlive the session, so
/// anything that records where SetShot lives records something temporary. Moving
/// the app in the Finder is what clears it; notarising does not.
///
/// `SecTranslocateIsTranslocatedURL` is the documented test, but the Security
/// framework does not surface that C function to Swift. The path marker is what
/// identifies the mount, and what that call reports on.
enum Translocation {

    static var isActive: Bool {
        isTranslocated(bundlePath: Bundle.main.bundlePath)
    }

    /// Split out from `isActive` so it can be tested without an actual translocated
    /// bundle, which cannot be arranged from a test.
    static func isTranslocated(bundlePath: String) -> Bool {
        bundlePath.contains("/AppTranslocation/")
    }

    /// Where the app really lives when macOS is running a translocated copy of it.
    ///
    /// A translocated bundle knows nothing about where it came from, and
    /// `SecTranslocateCreateOriginalPathForURL` is the only way to ask. Swift does not
    /// see that function, so it is resolved from the already-loaded Security framework
    /// at runtime rather than linked against.
    static func originalBundleURL() -> URL? {
        guard isActive else { return Bundle.main.bundleURL }
        typealias OriginalPathForURL = @convention(c)
            (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                 "SecTranslocateCreateOriginalPathForURL") else { return nil }
        let originalPath = unsafeBitCast(symbol, to: OriginalPathForURL.self)
        guard let result = originalPath(Bundle.main.bundleURL as CFURL, nil) else { return nil }
        return result.takeRetainedValue() as URL
    }

    enum MoveFailure: LocalizedError {
        case originalNotFound
        case directoryNotWritable(URL)
        case alreadyThere(URL)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .originalNotFound:
                return "SetShot could not work out where it was opened from."
            case .directoryNotWritable(let url):
                return "SetShot cannot write to \(url.path)."
            case .alreadyThere(let url):
                return "There is already a copy of SetShot at \(url.path)."
            case .failed(let reason):
                return reason
            }
        }
    }

    /// Moves the real app into the Applications folder and answers where it went.
    ///
    /// The translocated copy is a read-only mount and cannot be moved; what moves is
    /// the original the mount was made from. `replacingExisting` sends an older copy
    /// at the destination to the trash rather than deleting it, so a mistake here is
    /// recoverable.
    ///
    /// The directory is a parameter so this can be tested without writing to
    /// /Applications.
    @discardableResult
    static func moveToApplications(
        into directory: URL = URL(fileURLWithPath: "/Applications"),
        replacingExisting: Bool = false
    ) throws -> URL {
        guard let source = originalBundleURL() else { throw MoveFailure.originalNotFound }
        let fileManager = FileManager.default
        guard fileManager.isWritableFile(atPath: directory.path) else {
            throw MoveFailure.directoryNotWritable(directory)
        }
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            guard replacingExisting else { throw MoveFailure.alreadyThere(destination) }
            do {
                try fileManager.trashItem(at: destination, resultingItemURL: nil)
            } catch {
                throw MoveFailure.failed("The copy already in \(directory.path) could not be "
                    + "moved to the Trash: \(error.localizedDescription)")
            }
        }
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            throw MoveFailure.failed(error.localizedDescription)
        }
        return destination
    }

    /// Kept short on purpose. An alert cannot be widened -- AppKit sizes it and long
    /// text simply wraps into a narrow column -- and the HIG asks for a title and a
    /// sentence or two, not paragraphs. The buttons say what will happen, so this only
    /// has to say why it is being asked.
    static let advice = """
        SetShot is running from a translocated copy that macOS made because it was \
        opened from where it was unzipped rather than from your Applications folder.

        Scheduled snapshots cannot run and updates cannot install from there.
        """

    /// Only for when the move fails and the drag is back on the user.
    static let manualSteps =
        "Quit SetShot, drag it to your Applications folder, and open it again from there."
}
