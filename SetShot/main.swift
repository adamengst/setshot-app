import Foundation

// Every CLI mode is handled before the SwiftUI lifecycle; see LaunchArguments.
switch LaunchArguments.resolve(CommandLine.arguments) {
case .cli(let flag):
    LaunchArguments.cliModes[flag]!() // each writes stdout and calls exit(0)
case .unrecognised(let unknown):
    // Exiting turns a version mismatch into an error the caller can see.
    let available = LaunchArguments.cliModes.keys.sorted() + LaunchArguments.appFlags.sorted()
    FileHandle.standardError.write(Data("""
        SetShot: unrecognised option \(unknown)
        Available: \(available.joined(separator: ", "))

        """.utf8))
    exit(64) // EX_USAGE
case .app:
    break
}

SetShotApp.main()
