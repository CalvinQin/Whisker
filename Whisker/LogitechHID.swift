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
    case smartShift = 0x00C4
    case dpiSwitch = 0x00FD
}

enum HIDPPFeature: UInt16 {
    case root = 0x0000
    case featureSet = 0x0001
    case deviceNameType = 0x0005
    case batteryLevel = 0x1000
    case unifiedBattery = 0x1001
    case reprogControlsV4 = 0x1B04
    case adjustableDPI = 0x2201
}

struct HIDPP20 {
    static let REPORT_ID_SHORT: UInt8 = 0x10
    static let REPORT_ID_LONG: UInt8 = 0x11
    
    static func buildGetFeatureIndex(feature: HIDPPFeature, deviceIndex: UInt8 = 0x01) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = REPORT_ID_LONG
        report[1] = deviceIndex
        report[2] = 0x00 // Root Feature Index is always 0
        report[3] = 0x00 // function 0x0: GetFeature
        report[4] = UInt8(feature.rawValue >> 8)
        report[5] = UInt8(feature.rawValue & 0xFF)
        return report
    }
}
