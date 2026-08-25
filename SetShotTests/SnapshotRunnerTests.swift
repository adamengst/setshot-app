import XCTest
import MusicKit
@testable import SetShot

final class SnapshotRunnerTests: XCTestCase {

    /// Media capture follows the authorization alone. It used to also require a
    /// stored preference that the Settings pane wrote to mirror the authorization,
    /// which meant granting the permission in System Settings left capture off until
    /// the pane happened to be opened — silently skipping the Music and TV domains.
    func testMediaCaptureFollowsTheAuthorizationNotAStoredPreference() {
        let key = "CheckMusicSettings"
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }

        let authorized = MusicAuthorization.currentStatus == .authorized
        for stored in [true, false] {
            defaults.set(stored, forKey: key)
            XCTAssertEqual(SnapshotRunner.musicEnabled(), authorized,
                           "The stored preference must not affect the answer (was \(stored))")
        }
    }

    /// currentStatus does not prompt, unlike request(). Calling it while undecided
    /// must stay false so the media domains are skipped and no dialog can appear.
    func testUndecidedAuthorizationNeverEnablesCapture() {
        if MusicAuthorization.currentStatus == .notDetermined {
            XCTAssertFalse(SnapshotRunner.musicEnabled())
        }
    }
}
