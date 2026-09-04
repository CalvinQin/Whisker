import Foundation

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard condition() else {
        fatalError("\(message) (\(file):\(line))")
    }
}

@main
struct HIDPPReprogControlsTests {
    static func main() {
        let diversion = HIDPPReprogControls.temporaryDiversionParameters(for: 0x00D0)
        expect(diversion == [0x00, 0xD0, 0x03, 0x00, 0x00], "Unexpected diversion parameters")
        let diversionReset = HIDPPReprogControls.temporaryDiversionParameters(for: 0x00D0, enabled: false)
        expect(diversionReset == [0x00, 0xD0, 0x02, 0x00, 0x00], "Unexpected diversion reset parameters")

        let request = HIDPP20.buildFeatureRequest(
            deviceIndex: 0xFF,
            featureIndex: 0x0B,
            functionID: 3,
            softwareID: 5,
            parameters: diversion
        )
        expect(Array(request.prefix(9)) == [0x11, 0xFF, 0x0B, 0x35, 0x00, 0xD0, 0x03, 0x00, 0x00], "Unexpected setCidReporting request")

        var controlInfoReport = [UInt8](repeating: 0, count: 20)
        controlInfoReport[4] = 0x00
        controlInfoReport[5] = 0xD0
        controlInfoReport[8] = 0x31
        controlInfoReport[12] = 0x01
        let info = HIDPPReprogControls.parseControlInfo(from: controlInfoReport)
        expect(info?.cid == 0x00D0, "Control ID was not decoded")
        expect(info?.isDivertible == true, "Divert capability was not decoded")
        expect(info?.supportsRawXY == true, "Raw XY capability was not decoded")

        var pressedReport = [UInt8](repeating: 0, count: 20)
        pressedReport[4] = 0x00
        pressedReport[5] = 0xD0
        pressedReport[6] = 0x00
        pressedReport[7] = 0xC3
        expect(
            HIDPPReprogControls.divertedButtonIDs(from: pressedReport) == [0x00D0, 0x00C3],
            "Pressed control IDs were not decoded"
        )
        expect(
            HIDPPReprogControls.divertedButtonIDs(from: [UInt8](repeating: 0, count: 20)).isEmpty,
            "Release report should contain no pressed controls"
        )

        var batteryReport = [UInt8](repeating: 0, count: 20)
        batteryReport[4] = 100
        expect(HIDPPBattery.percentage(from: batteryReport) == 100, "Battery percentage was not decoded")
        batteryReport[4] = 0
        expect(HIDPPBattery.percentage(from: batteryReport) == nil, "Unknown battery level should be ignored")
        batteryReport[4] = 101
        expect(HIDPPBattery.percentage(from: batteryReport) == nil, "Invalid battery level should be ignored")

        let bluetoothJSON = #"{"SPBluetoothDataType":[{"device_connected":[{"M720 Triathlon":{"device_batteryLevelMain":"100%"}}]}]}"#
        expect(
            SystemBluetoothBattery.percentage(from: Data(bluetoothJSON.utf8), matching: "M720 Triathlon") == 100,
            "System Bluetooth battery percentage was not decoded"
        )
        expect(
            SystemBluetoothBattery.percentage(from: Data(bluetoothJSON.utf8), matching: "MX Master") == nil,
            "Battery percentage from another device should be ignored"
        )

        print("HIDPPReprogControlsTests passed")
    }
}
