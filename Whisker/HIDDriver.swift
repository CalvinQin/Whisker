import Foundation
import IOKit
import IOKit.hid
import os.log

private func debugLog(_ msg: String) {
    let line = "[\(Date())] \(msg)\n"
    let path = NSHomeDirectory() + "/Desktop/whisker_hid.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

enum ConnectionType: String {
    case usb = "USB"
    case receiver = "Receiver"
    case bluetooth = "Bluetooth"
    case unknown = "Unknown"
    
    var iconName: String {
        switch self {
        case .usb: return "cable.connector"
        case .receiver: return "antenna.radiowaves.left.and.right"
        case .bluetooth: return "bluetooth"
        case .unknown: return "questionmark.circle"
        }
    }
}

class HIDDriver: ObservableObject {
    private var manager: IOHIDManager?
    @Published var batteryLevel: Int = 0
    @Published var isConnected: Bool = false
    @Published var deviceName: String = "No Device"
    @Published var connectionType: ConnectionType = .unknown
    
    // UI can set this to prioritize which device to show status for
    var targetDeviceName: String = "" {
        didSet {
            updatePrimaryDevice()
        }
    }
    
    // Store all connected devices
    private var allDevices: [String: (IOHIDDevice, ConnectionType)] = [:]
    
    private var activeDevice: IOHIDDevice?
    private var featureIndices: [UInt16: UInt8] = [:]
    private var deviceIndex: UInt8 = 0xFF
    private var pendingDiscovery: [UInt16] = []
    
    init() {
        debugLog("=== HIDDriver init ===")
        setupHIDManager()
    }
    
    private func setupHIDManager() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let deviceMatch: [[String: Any]] = [
            [kIOHIDVendorIDKey: 0x046D], // Logitech
            [kIOHIDVendorIDKey: 0x373B]  // ATK / VGN
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager!, deviceMatch as CFArray)
        
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceMatchingCallback(manager!, { (ctx, result, sender, device) in
            Unmanaged<HIDDriver>.fromOpaque(ctx!).takeUnretainedValue().handleDeviceConnected(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager!, { (ctx, result, sender, device) in
            Unmanaged<HIDDriver>.fromOpaque(ctx!).takeUnretainedValue().handleDeviceDisconnected(device)
        }, context)
        
        // CRITICAL: Must use main RunLoop, not CFRunLoopGetCurrent() which may be a background thread
        IOHIDManagerScheduleWithRunLoop(manager!, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let openResult = IOHIDManagerOpen(manager!, IOOptionBits(kIOHIDOptionsTypeNone))
        debugLog("HIDManager opened, result=\(openResult), scheduled on MAIN RunLoop")
    }
    
    private func handleDeviceConnected(_ device: IOHIDDevice) {
        let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Logitech"
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
        let maxOutput = IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
        
        debugLog("Device=\(name) UsagePage=0x\(String(format:"%04X",usagePage)) Transport='\(transport)' MaxOutput=\(maxOutput)")
        
        // Detect connection type from transport string
        let connType: ConnectionType
        let transportLower = transport.lowercased()
        if transportLower.contains("bluetooth") || transportLower.contains("nearlink") || transportLower == "bluetoothlowenergy" || transportLower == "btle" {
            connType = .bluetooth
            deviceIndex = 0xFF
        } else if transportLower == "usb" {
            let nameLower = name.lowercased()
            if nameLower.contains("receiver") || nameLower.contains("unifying") || nameLower.contains("bolt") || nameLower.contains("nano") {
                connType = .receiver
                deviceIndex = 0x01
            } else {
                connType = .usb
                deviceIndex = 0xFF
            }
        } else {
            // Fallback: check model name
            let nameLower = name.lowercased()
            if nameLower.contains("m720") || nameLower.contains("mx") || nameLower.contains("triathlon") {
                connType = .bluetooth
                deviceIndex = 0xFF
            } else {
                connType = .unknown
                deviceIndex = 0xFF
            }
        }
        
        debugLog("Connection type: \(connType.rawValue) deviceIndex=0x\(String(format:"%02X",deviceIndex))")
        
        allDevices[name] = (device, connType)
        updatePrimaryDevice()
        
        // HID++ capable interface detection (Only for Logitech 0x046D)
        let vendorId = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let isLogitech = vendorId == 0x046D
        let isHIDPPCapable = isLogitech && ((usagePage >= 0xFF00 && maxOutput >= 7) || (maxOutput >= 20))
        if isHIDPPCapable && activeDevice == nil {
            activeDevice = device
            
            // Open the vendor-specific interface
            let openRes = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            debugLog("✅ HID++ interface found! UsagePage=0x\(String(format:"%04X",usagePage)) MaxOutput=\(maxOutput) OpenRes=\(openRes)")
            
            let bufSize = 64
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
            IOHIDDeviceRegisterInputReportCallback(device, buf, bufSize, { (ctx, result, sender, type, reportId, report, len) in
                Unmanaged<HIDDriver>.fromOpaque(ctx!).takeUnretainedValue().processReport(reportId: reportId, report: report, length: len)
            }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.discoverFeature(.batteryLevel)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.discoverFeature(.unifiedBattery)
            }

        }
    }
    
    private func handleDeviceDisconnected(_ device: IOHIDDevice) {
        if let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String {
            allDevices.removeValue(forKey: name)
        }
        
        if activeDevice == device {
            activeDevice = nil
            featureIndices.removeAll()
        }
        updatePrimaryDevice()
    }
    
    private func updatePrimaryDevice() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Try to find target device first
            var bestMatch: (name: String, device: IOHIDDevice, type: ConnectionType)? = nil
            
            if !self.targetDeviceName.isEmpty {
                if let match = self.allDevices.first(where: { $0.key.lowercased().contains(self.targetDeviceName.lowercased()) }) {
                    bestMatch = (match.key, match.value.0, match.value.1)
                } else if let match = self.allDevices.first(where: { self.targetDeviceName.lowercased().contains($0.key.lowercased()) }) {
                    bestMatch = (match.key, match.value.0, match.value.1)
                }
            }
            
            // Fallback to any device
            if bestMatch == nil, let first = self.allDevices.first {
                bestMatch = (first.key, first.value.0, first.value.1)
            }
            
            if let best = bestMatch {
                self.isConnected = true
                self.deviceName = best.name
                self.connectionType = best.type
            } else {
                self.isConnected = false
                self.deviceName = "No Device"
                self.connectionType = .unknown
                self.batteryLevel = 0
            }
        }
    }
    
    func discoverFeature(_ feature: HIDPPFeature) {
        guard let device = activeDevice else {
            debugLog("⚠️ No HID++ interface for \(feature) discovery")
            return
        }
        pendingDiscovery.append(feature.rawValue)
        let report = HIDPP20.buildGetFeatureIndex(feature: feature, deviceIndex: deviceIndex)
        let hexStr = report.prefix(10).map { String(format:"%02X",$0) }.joined(separator:" ")
        debugLog("→ Discover 0x\(String(format:"%04X",feature.rawValue)): [\(hexStr)]")
        
        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), report, report.count)
        if result != kIOReturnSuccess {
            debugLog("⚠️ Output report failed (\(result)), trying Feature report...")
            let r2 = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(report[0]), report, report.count)
            debugLog(r2 == kIOReturnSuccess ? "✅ Feature report worked!" : "❌ Feature report failed: \(r2)")
        } else {
            debugLog("✅ Output report sent OK")
        }
    }
    
    private func processReport(reportId: UInt32, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        let data = Array(UnsafeBufferPointer(start: report, count: length))
        guard data.count >= 7 else { return }
        
        // Validate it's a HID++ protocol report or a standard BLE response containing HID++ payload
        // Over USB/Receiver: 0x10 (short), 0x11 (long)
        // Over BLE (standard mouse interface): Responses often arrive on report ID 0x02
        guard data[0] == HIDPP20.REPORT_ID_LONG || data[0] == HIDPP20.REPORT_ID_SHORT || data[0] == 0x02 else {
            return
        }
        
        // For report ID 0x02 over BLE, if data is mostly zeros with just X Y movement, we should skip it
        // to avoid draining the pendingDiscovery queue. Real HID++ responses usually have data[1] = 0x00 and data[2] = featureIdx
        if data[0] == 0x02 {
            // Very hacky heuristics to distinguish standard mouse movement from HID++ response
            // True HID++ response on 0x02 has data[1] = 0x00 (software ID), and data[2] > 0 (feature ID / command).
            // A regular mouse movement has buttons in [1], X in [2], Y in [3]
            // If data[1] is non-zero (buttons pressed) or data[2] is huge (large movement), it's probably not HID++
            if data[1] != 0x00 { return }
        }
        
        let rFeatureIdx = data[2]
        
        let hexStr = data.prefix(min(data.count, 20)).map { String(format:"%02X",$0) }.joined(separator:" ")
        debugLog("← [\(hexStr)]")
        
        // Error response
        if rFeatureIdx == 0xFF {
            debugLog("⚠️ Error response code=\(data[4])")
            return
        }
        
        // Feature Discovery (root index 0x00)
        if rFeatureIdx == 0x00 {
            // IRoot getFeatureIndex response:
            // data[4] = discovered featureIndex (the INDEX, not the feature ID!)
            // data[5] = featureType
            let discoveredIdx = data[4]
            
            // Match this response to the first pending discovery request
            let requestedFeatureID: UInt16
            if !pendingDiscovery.isEmpty {
                requestedFeatureID = pendingDiscovery.removeFirst()
            } else {
                debugLog("⚠️ Got IRoot response but no pending discovery")
                return
            }
            
            if discoveredIdx > 0 {
                debugLog("✅ Feature 0x\(String(format:"%04X",requestedFeatureID)) discovered at index \(discoveredIdx)")
                featureIndices[requestedFeatureID] = discoveredIdx
                if requestedFeatureID == HIDPPFeature.batteryLevel.rawValue || requestedFeatureID == HIDPPFeature.unifiedBattery.rawValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.requestBatteryStatus(featureID: requestedFeatureID)
                    }
                }
            } else {
                debugLog("❌ Feature 0x\(String(format:"%04X",requestedFeatureID)) not supported (index=0)")
            }
            return
        }
        
        // Battery Level Status (0x1000)
        if let bIdx = featureIndices[HIDPPFeature.batteryLevel.rawValue], rFeatureIdx == bIdx {
            let level = Int(data[4])
            debugLog("🔋 Battery (0x1000): \(level)%")
            DispatchQueue.main.async { if level > 0 { self.batteryLevel = level } }
            return
        }
        
        // Unified Battery (0x1001)
        if let uIdx = featureIndices[HIDPPFeature.unifiedBattery.rawValue], rFeatureIdx == uIdx {
            let soc = Int(data[4])
            let qual = data[5]
            let level = soc > 0 ? soc : ([1:5, 3:25, 5:60, 7:100][qual] ?? 50)
            debugLog("🔋 Battery (0x1001): \(level)%")
            DispatchQueue.main.async { self.batteryLevel = level }
            return
        }
        

    }
    
    func requestBatteryStatus(featureID: UInt16? = nil) {
        guard let device = activeDevice else { return }
        let target = featureID ?? HIDPPFeature.batteryLevel.rawValue
        guard let index = featureIndices[target] ?? featureIndices[HIDPPFeature.unifiedBattery.rawValue] else {
            discoverFeature(.batteryLevel)
            return
        }
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = HIDPP20.REPORT_ID_LONG
        report[1] = deviceIndex
        report[2] = index
        report[3] = 0x00
        debugLog("🔋 Requesting battery (index=\(index) devIdx=0x\(String(format:"%02X",deviceIndex)))")
        IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), report, report.count)
    }
    
}
