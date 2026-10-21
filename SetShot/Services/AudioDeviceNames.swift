import Foundation

/// Names for the audio device identifiers macOS stores in preferences.
///
/// FaceTime's microphone, the Sound pane's preferred devices and the Screenshot
/// tool's microphone are all recorded as Core Audio device UIDs, which read as
/// "14-14-7D-E4-A5-D9:input" or "AppleUSBAudioEngine:Audio Technica Corp:ATR2100x-USB
/// Microphone:4130000:1". A USB device carries its product name in the UID itself.
/// A Bluetooth device carries only its address, so the name comes from the list of
/// paired devices — a live lookup, like a default handler's app name, because a
/// device's name is its identity rather than a setting a comparison could be about.
/// A device no longer paired falls back to its address.
enum AudioDeviceNames {
    static func name(for value: String) -> String? {
        if let product = usbProductName(in: value) { return product }
        if let address = bluetoothAddress(in: value) { return pairedBluetoothNames[address] }
        return nil
    }

    /// "AppleUSBAudioEngine:<vendor>:<product>:<location>:<index>" → product.
    static func usbProductName(in value: String) -> String? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0] == "AppleUSBAudioEngine" else { return nil }
        let product = parts[2].trimmingCharacters(in: .whitespaces)
        return product.isEmpty ? nil : product
    }

    /// A Bluetooth address, written with colons or dashes and optionally followed by
    /// ":input" or ":output", normalized to the uppercase, colon-separated form the
    /// paired-device list uses.
    static func bluetoothAddress(in value: String) -> String? {
        let ns = value as NSString
        guard let match = addressRegex.firstMatch(in: value, range: NSRange(location: 0, length: ns.length))
        else { return nil }
        return ns.substring(with: match.range(at: 1))
            .replacingOccurrences(of: "-", with: ":")
            .uppercased()
    }

    private static let addressRegex = try! NSRegularExpression(
        pattern: #"^((?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2})(?::(?:input|output))?$"#)

    /// Address → name for every paired device, read once. system_profiler answers in
    /// well under a tenth of a second and lists devices that are not connected, which
    /// is the usual state of headphones by the time a comparison is read.
    static let pairedBluetoothNames: [String: String] = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [:] }
        // Read before waiting: a full pipe would otherwise block the child forever.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parseBluetoothNames(json: data)
    }()

    static func parseBluetoothNames(json: Data) -> [String: String] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return [:] }
        var names: [String: String] = [:]
        for controller in controllers {
            for section in ["device_connected", "device_not_connected"] {
                for device in controller[section] as? [[String: Any]] ?? [] {
                    for (name, info) in device {
                        guard let address = (info as? [String: Any])?["device_address"] as? String
                        else { continue }
                        names[address.replacingOccurrences(of: "-", with: ":").uppercased()] = name
                    }
                }
            }
        }
        return names
    }
}
