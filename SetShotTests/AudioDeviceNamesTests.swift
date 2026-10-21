import XCTest
@testable import SetShot

final class AudioDeviceNamesTests: XCTestCase {

    func testUSBDeviceIsNamedFromItsUID() {
        XCTAssertEqual(AudioDeviceNames.usbProductName(
            in: "AppleUSBAudioEngine:Audio Technica Corp:ATR2100x-USB Microphone:4130000:1"),
            "ATR2100x-USB Microphone")
    }

    func testBluetoothAddressIsReadInEitherForm() {
        XCTAssertEqual(AudioDeviceNames.bluetoothAddress(in: "14-14-7d-e4-a5-d9:input"), "14:14:7D:E4:A5:D9")
        XCTAssertEqual(AudioDeviceNames.bluetoothAddress(in: "14:14:7D:E4:A5:D9"), "14:14:7D:E4:A5:D9")
    }

    func testOtherValuesAreNotTakenForDevices() {
        XCTAssertNil(AudioDeviceNames.bluetoothAddress(in: "BuiltInMicrophoneDevice"))
        XCTAssertNil(AudioDeviceNames.bluetoothAddress(in: "14:14:7D:E4:A5:D9:extra"))
        XCTAssertNil(AudioDeviceNames.usbProductName(in: "BuiltInSpeakerDevice"))
    }

    func testPairedDevicesAreReadFromBothSections() {
        let json = """
        {"SPBluetoothDataType":[{
          "device_connected":[{"Magic Mouse 2":{"device_address":"18:65:90:BC:9E:41"}}],
          "device_not_connected":[{"AirPods Pro 2":{"device_address":"14:14:7D:E4:A5:D9"}}]
        }]}
        """
        let names = AudioDeviceNames.parseBluetoothNames(json: Data(json.utf8))
        XCTAssertEqual(names["14:14:7D:E4:A5:D9"], "AirPods Pro 2")
        XCTAssertEqual(names["18:65:90:BC:9E:41"], "Magic Mouse 2")
    }
}
