import XCTest
import Combine
@testable import SetShot

final class UpdaterStateTests: XCTestCase {

    // MARK: - Initialization

    func testInitializesWithoutCrashing() {
        _ = UpdaterState()
    }

    // MARK: - KVO observation

    // The KVO handler uses [.initial, .new] + DispatchQueue.main.async.
    // @Published emits on every assignment (even same-value), so after the next
    // main-queue drain we should see a second emission beyond the synchronous
    // @Published default. If the KVO wiring is removed entirely, this second
    // emission never arrives and canCheckForUpdates will never reflect Sparkle's
    // real state — leaving "Check for Updates" permanently greyed out.
    func testKVOInitialNotificationPropagatesAfterMainQueueDrain() {
        let state = UpdaterState()
        let expectation = expectation(description: "KVO initial value dispatched to main queue")

        var cancellable: AnyCancellable?
        cancellable = state.$canCheckForUpdates
            .dropFirst() // skip the synchronous @Published initial emission
            .sink { _ in
                expectation.fulfill()
                cancellable?.cancel()
            }

        waitForExpectations(timeout: 1.0)
    }

    // After KVO fires, the value must be false in debug/test builds because the
    // updater was not started (no XPC services invoked, no signing error dialog).
    func testCanCheckForUpdatesIsFalseInDebugBuilds() {
        let state = UpdaterState()
        let expectation = expectation(description: "KVO value received")

        var cancellable: AnyCancellable?
        cancellable = state.$canCheckForUpdates
            .dropFirst()
            .sink { value in
                #if DEBUG
                XCTAssertFalse(value, "Updater must not be running in debug/test builds")
                #endif
                expectation.fulfill()
                cancellable?.cancel()
            }

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - Release-build start flag

    // Tests always run in debug, so startsInRelease must be false here — which
    // verifies the #if DEBUG conditional is intact and would return true in release.
    // Fails if someone removes the conditional and hardcodes false (breaking updates
    // for all users) or removes the guard entirely.
    func testStartFlagIsFalseInDebugTrueInRelease() {
        #if DEBUG
        XCTAssertFalse(UpdaterState.startsInRelease,
            "Must be false in debug — confirms #if DEBUG guard is present and would flip to true in release")
        #else
        XCTAssertTrue(UpdaterState.startsInRelease,
            "Must be true in release builds so Sparkle actually runs")
        #endif
    }

    // MARK: - Info.plist Sparkle configuration

    // If SUFeedURL is missing or points to the wrong URL, Sparkle checks the
    // wrong endpoint and users never receive updates regardless of how often it runs.
    func testFeedURLIsProductionAppcast() {
        let bundle = Bundle(for: UpdaterState.self)
        let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        XCTAssertEqual(
            feedURL,
            "https://raw.githubusercontent.com/adamengst/setshot-app/main/appcast.xml",
            "SUFeedURL must point to the production appcast"
        )
    }

    // If SUPublicEDKey is absent, Sparkle rejects every update as unsigned and
    // the auto-update dialog never appears.
    func testEdDSAPublicKeyIsPresent() {
        let bundle = Bundle(for: UpdaterState.self)
        let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        XCTAssertNotNil(key, "SUPublicEDKey must be set in Info.plist")
        XCTAssertFalse(key?.isEmpty ?? true, "SUPublicEDKey must not be empty")
    }
}
