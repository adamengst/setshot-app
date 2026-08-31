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

    static let advice = """
        SetShot is running from a temporary copy that macOS made because it was \
        opened from where it was unzipped rather than from your Applications folder. \
        That copy sits in a different place every time it launches.

        Scheduled snapshots cannot run from it, because the schedule would point at a \
        folder macOS throws away, and updates cannot install.

        Quit SetShot, drag it to your Applications folder, and open it from there.
        """
}
