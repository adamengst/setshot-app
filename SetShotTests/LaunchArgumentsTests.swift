import XCTest
@testable import SetShot

/// main.swift decides from `--` flags whether a launch is a CLI mode, the app, or an
/// error. 1.0b27 and 1.0b28 shipped rejecting `--background-snapshot`, the flag the
/// scheduler writes into its LaunchAgent, so every scheduled run exited 64 before
/// taking a snapshot. These tests tie the two together.
final class LaunchArgumentsTests: XCTestCase {

    private let binary = "/Applications/SetShot.app/Contents/MacOS/SetShot"

    func testEveryScheduleLaunchesTheApp() {
        let schedules: [SnapshotSchedule] = [
            .interval(minutes: 60),
            .daily(hour: 8, minute: 0),
            .weekly(weekday: 2, hour: 8, minute: 0),
            .monthly(day: 1, hour: 8, minute: 0),
        ]
        for schedule in schedules {
            let plist = SchedulerManager.launchAgentPlist(schedule: schedule, executablePath: binary)
            let arguments = try? XCTUnwrap(plist["ProgramArguments"] as? [String])
            XCTAssertEqual(arguments?.first, binary)
            XCTAssertEqual(LaunchArguments.resolve(arguments ?? []), .app, "\(schedule)")
        }
    }

    func testANormalLaunchIsTheApp() {
        XCTAssertEqual(LaunchArguments.resolve([binary]), .app)
        XCTAssertEqual(LaunchArguments.resolve([binary, "-NSDocumentRevisionsDebugMode", "YES"]), .app)
    }

    func testCLIModesAreClaimed() {
        for flag in LaunchArguments.cliModes.keys {
            XCTAssertEqual(LaunchArguments.resolve([binary, flag]), .cli(flag))
        }
    }

    func testTheLongestFlagWins() {
        XCTAssertEqual(LaunchArguments.resolve([binary, "--flatten-plist", "--flatten-plist-batch"]),
                       .cli("--flatten-plist-batch"))
    }

    func testAnUnknownFlagIsRejected() {
        XCTAssertEqual(LaunchArguments.resolve([binary, "--no-such-mode"]), .unrecognised("--no-such-mode"))
        XCTAssertEqual(LaunchArguments.resolve([binary, LaunchArguments.backgroundSnapshot, "--no-such-mode"]),
                       .unrecognised("--no-such-mode"))
    }

    func testAppAndCLIFlagsDoNotOverlap() {
        XCTAssertTrue(LaunchArguments.appFlags.isDisjoint(with: LaunchArguments.cliModes.keys))
    }
}
