import Foundation

struct HIDPPMessage {
    let deviceIndex: UInt8
    let featureIndex: UInt8
    let functionID: UInt8
    let parameters: [UInt8]
    
    func encodeLong() -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = 0x11 // Long report ID
        report[1] = deviceIndex
        report[2] = featureIndex
        report[3] = (functionID << 4) // Function ID in high nibble
        for (i, param) in parameters.enumerated() {
            if i < 16 {
                report[4 + i] = param
            }
        }
        return report
    }
    
    static func decode(data: [UInt8]) -> HIDPPMessage? {
        guard data.count >= 4 else { return nil }
        let reportID = data[0]
        guard reportID == 0x11 || reportID == 0x10 else { return nil }
        
        return HIDPPMessage(
            deviceIndex: data[1],
            featureIndex: data[2],
            functionID: data[3] >> 4,
            parameters: Array(data[4...])
        )
    }
}

class HIDPPManager {
    // Known Feature IDs
    static let FEATURE_ROOT: UInt8 = 0x00
    static let FEATURE_FEATURE_SET: UInt8 = 0x01
    static let FEATURE_BATTERY: UInt16 = 0x1000 // Placeholder, requires discovery
    
    static func batteryRequest(deviceIndex: UInt8 = 0xFF, featureIndex: UInt8) -> HIDPPMessage {
        return HIDPPMessage(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionID: 0x0, // GetBatteryLevelStatus
            parameters: []
        )
    }
}
