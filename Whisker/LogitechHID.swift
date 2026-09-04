import Foundation

struct LogitechDevice {
    let name: String
    let vendorID: Int = 0x046D
    let productID: Int
    
    static let gProWireless = LogitechDevice(name: "G Pro Wireless", productID: 0x4079)
    static let m720 = LogitechDevice(name: "M720 Triathlon", productID: 0xB015)
}

enum LogitechCID: UInt16 {
    case leftClick = 0x0050
    case rightClick = 0x0051
    case middleClick = 0x0052
    case backButton = 0x0053
    case forwardButton = 0x0056
    case gestureButton = 0x00C3
    case multiPlatformGestureButton = 0x00D0
    case smartShift = 0x00C4
    case dpiSwitch = 0x00FD
}

enum HIDPPFeature: UInt16 {
    case root = 0x0000
    case featureSet = 0x0001
    case deviceNameType = 0x0005
    case batteryLevel = 0x1000
    case batteryVoltage = 0x1001
    case reprogControlsV4 = 0x1B04
    case adjustableDPI = 0x2201
}

struct HIDPP20 {
    static let REPORT_ID_SHORT: UInt8 = 0x10
    static let REPORT_ID_LONG: UInt8 = 0x11
    
    static func buildGetFeatureIndex(
        feature: HIDPPFeature,
        deviceIndex: UInt8 = 0x01,
        softwareID: UInt8 = 1
    ) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = REPORT_ID_LONG
        report[1] = deviceIndex
        report[2] = 0x00 // Root Feature Index is always 0
        report[3] = softwareID & 0x0F // function 0x0: GetFeature
        report[4] = UInt8(feature.rawValue >> 8)
        report[5] = UInt8(feature.rawValue & 0xFF)
        return report
    }

    static func buildFeatureRequest(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionID: UInt8,
        softwareID: UInt8,
        parameters: [UInt8] = []
    ) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = REPORT_ID_LONG
        report[1] = deviceIndex
        report[2] = featureIndex
        report[3] = (functionID << 4) | (softwareID & 0x0F)
        for (index, value) in parameters.prefix(16).enumerated() {
            report[4 + index] = value
        }
        return report
    }
}

struct HIDPPReprogControlInfo: Equatable {
    let cid: UInt16
    let flags: UInt8
    let supportsRawXY: Bool

    var isDivertible: Bool { flags & 0x20 != 0 }
}

enum HIDPPReprogControls {
    static let gestureCandidates: Set<UInt16> = [
        LogitechCID.multiPlatformGestureButton.rawValue,
        LogitechCID.gestureButton.rawValue
    ]

    static func parseControlInfo(from report: [UInt8]) -> HIDPPReprogControlInfo? {
        guard report.count >= 13 else { return nil }
        return HIDPPReprogControlInfo(
            cid: UInt16(report[4]) << 8 | UInt16(report[5]),
            flags: report[8],
            supportsRawXY: report[12] & 0x01 != 0
        )
    }

    static func divertedButtonIDs(from report: [UInt8]) -> Set<UInt16> {
        guard report.count >= 12 else { return [] }
        var result: Set<UInt16> = []
        for index in stride(from: 4, through: 10, by: 2) {
            let cid = UInt16(report[index]) << 8 | UInt16(report[index + 1])
            if cid != 0 {
                result.insert(cid)
            }
        }
        return result
    }

    static func temporaryDiversionParameters(for cid: UInt16, enabled: Bool = true) -> [UInt8] {
        [
            UInt8(cid >> 8),
            UInt8(cid & 0xFF),
            enabled ? 0x03 : 0x02, // Always mark the temporary-divert bit as valid.
            0x00,
            0x00
        ]
    }
}

enum HIDPPBattery {
    static func percentage(from report: [UInt8]) -> Int? {
        guard report.count > 4 else { return nil }
        let percentage = Int(report[4])
        return (1...100).contains(percentage) ? percentage : nil
    }
}

enum SystemBluetoothBattery {
    static func percentage(from data: Data, matching deviceName: String) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }

        let target = deviceName.lowercased()
        for section in sections {
            guard let connectedDevices = section["device_connected"] as? [[String: Any]] else { continue }
            for devices in connectedDevices {
                for (name, value) in devices {
                    let candidate = name.lowercased()
                    guard candidate == target || candidate.contains(target) || target.contains(candidate),
                          let details = value as? [String: Any],
                          let rawLevel = details["device_batteryLevelMain"] as? String,
                          let percentage = Int(rawLevel.filter(\.isNumber)),
                          (1...100).contains(percentage) else { continue }
                    return percentage
                }
            }
        }
        return nil
    }
}
