import Foundation
import IOKit
import IOKit.hid

class HIDDriver: ObservableObject {
    private var manager: IOHIDManager?
    @Published var batteryLevel: Int = 0
    @Published var isConnected: Bool = false
    @Published var deviceName: String = "No Device"
    @Published var lastEvent: String = ""
    
    private var activeDevice: IOHIDDevice?
    private var featureIndices: [UInt16: UInt8] = [:]
    
    init() {
        setupHIDManager()
    }
    
    private func setupHIDManager() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDManagerOptionNone))
        let deviceMatch: [[String: Any]] = [[kIOHIDVendorIDKey: 0x046D]]
        IOHIDManagerSetDeviceMatchingMultiple(manager!, deviceMatch as CFArray)
        
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceMatchingCallback(manager!, { (context, result, sender, device) in
            Unmanaged<HIDDriver>.fromOpaque(context!).takeUnretainedValue().handleDeviceConnected(device)
        }, context)
        
        IOHIDManagerRegisterDeviceRemovalCallback(manager!, { (context, result, sender, device) in
            Unmanaged<HIDDriver>.fromOpaque(context!).takeUnretainedValue().handleDeviceDisconnected(device)
        }, context)
        
        IOHIDManagerScheduleWithRunLoop(manager!, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager!, IOOptionBits(kIOHIDManagerOptionNone))
    }
    
    private func handleDeviceConnected(_ device: IOHIDDevice) {
        self.activeDevice = device
        DispatchQueue.main.async {
            self.isConnected = true
            if let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String {
                self.deviceName = name
            }
        }
        
        let reportBufferSize = 64
        let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportBufferSize)
        IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, reportBufferSize, { (context, result, sender, type, reportId, report, reportLength) in
            Unmanaged<HIDDriver>.fromOpaque(context!).takeUnretainedValue().processReport(reportId: reportId, report: report, length: reportLength)
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        
        // Step 1: Discover Features
        discoverFeature(.batteryLevel)
        discoverFeature(.reprogControlsV4)
    }
    
    private func handleDeviceDisconnected(_ device: IOHIDDevice) {
        if self.activeDevice == device {
            self.activeDevice = nil
            DispatchQueue.main.async {
                self.isConnected = false
                self.deviceName = "No Device"
            }
        }
    }
    
    func discoverFeature(_ feature: HIDPPFeature) {
        guard let device = activeDevice else { return }
        let report = HIDPP20.buildGetFeatureIndex(feature: feature)
        IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), report, report.count)
    }
    
    private func processReport(reportId: UInt8, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        let data = Array(UnsafeBufferPointer(start: report, count: length))
        guard data.count >= 4 else { return }
        
        // Root Feature response
        if data[2] == 0x00 && (data[3] & 0xF0) == 0x00 { 
            let featureID = (UInt16(data[4]) << 8) | UInt16(data[5])
            let index = data[6]
            if index > 0 {
                featureIndices[featureID] = index
                print("Discovered Feature 0x\(String(featureID, radix: 16)) at index \(index)")
                if featureID == HIDPPFeature.batteryLevel.rawValue {
                    requestBatteryStatus()
                }
            }
        } 
        // Battery response
        else if let batteryIndex = featureIndices[HIDPPFeature.batteryLevel.rawValue], data[2] == batteryIndex {
            DispatchQueue.main.async {
                self.batteryLevel = Int(data[4])
            }
        }
        
        // Generic event logging for debugging
        DispatchQueue.main.async {
            self.lastEvent = "Report: \(data.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " "))"
        }
    }
    
    func requestBatteryStatus() {
        guard let device = activeDevice, let index = featureIndices[HIDPPFeature.batteryLevel.rawValue] else { return }
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = HIDPP20.REPORT_ID_LONG
        report[1] = 0xFF
        report[2] = index
        report[3] = 0x00 // GetBatteryLevelStatus
        IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), report, report.count)
    }
    
    func setDPI(dpi: Int) {
        // Implementation for setting DPI via HID++
        print("Setting DPI to \(dpi)")
    }
}
