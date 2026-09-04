import Foundation
import AppKit
import IOKit
import IOKit.hid
import os

private let hidLogger = Logger(subsystem: "com.haoqi.whisker", category: "HID")
private func debugLog(_ msg: String) {
#if DEBUG
    hidLogger.debug("\(msg, privacy: .public)")
#endif
}

private func statusLog(_ msg: String) {
    hidLogger.info("\(msg, privacy: .public)")
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
    private enum PendingHIDPPRequest {
        case discover(HIDPPFeature)
        case reprogCount
        case reprogControlInfo(Int)
        case reprogSet(UInt16)

        var isGestureConfiguration: Bool {
            switch self {
            case .discover(.reprogControlsV4), .reprogCount, .reprogControlInfo, .reprogSet:
                return true
            default:
                return false
            }
        }
    }

    private var manager: IOHIDManager?
    @Published var batteryLevel: Int = 0
    @Published var isConnected: Bool = false
    @Published var deviceName: String = "No Device"
    @Published var connectionType: ConnectionType = .unknown
    @Published private(set) var hasInputMonitoringPermission = false
    @Published private(set) var isGestureControlReady = false
    @Published private(set) var gestureControlConfigurationFailed = false
    @Published private(set) var hasDetectedGestureButton = false
    var rawButtonHandler: ((MouseButton, Bool) -> Void)?
    var primaryDeviceHandler: ((String) -> Void)?
    var gestureActionsEnabled = false {
        didSet {
            guard gestureActionsEnabled != oldValue else { return }
            if gestureActionsEnabled {
                configureGestureControlIfPossible()
            } else {
                disableGestureDiversion()
            }
        }
    }
    
    // UI can set this to prioritize which device to show status for
    var targetDeviceName: String = "" {
        didSet {
            if oldValue != targetDeviceName {
                if isM720(oldValue), !isM720(targetDeviceName) {
                    disableGestureDiversion()
                }
                updatePrimaryDevice()
                configureGestureControlIfPossible()
            }
        }
    }
    
    // Public getter for all connected devices to be used by UI menu
    var connectedDevices: [String: DeviceState] {
        return allDevices
    }
    
    // Store all connected devices with their individual states
    struct DeviceState {
        let device: IOHIDDevice
        let type: ConnectionType
        var batteryLevel: Int = 0
        var name: String
        let uniqueId: String
    }
    private var allDevices: [String: DeviceState] = [:]
    // Track the uniqueId of the device whose HID++ interface we're using
    private var activeDeviceUniqueId: String = ""
    
    private var activeDevice: IOHIDDevice?
    private var activeDeviceOpened = false
    private var inputReportBuffer: UnsafeMutablePointer<UInt8>?
    private var featureIndices: [UInt16: UInt8] = [:]
    private var deviceIndex: UInt8 = 0xFF
    private var pendingRequests: [UInt8: PendingHIDPPRequest] = [:]
    private var nextSoftwareID: UInt8 = 1
    private var reprogControlCount = 0
    private var nextReprogControlIndex = 0
    private var gestureCID: UInt16?
    private var rawXYGestureCandidate: UInt16?
    private var divertedGestureCID: UInt16?
    private var divertedButtonIDs: Set<UInt16> = []
    private var managerOpenSucceeded = false
    private var prefersSystemBluetoothBattery = false
    private var isSystemBatteryRefreshInFlight = false
    private var terminationObserver: NSObjectProtocol?
    
    init() {
        debugLog("=== HIDDriver init ===")
        refreshInputMonitoringPermission()
        setupHIDManager()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.teardownHIDManager()
        }
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
        IOHIDManagerRegisterInputValueCallback(manager!, { (ctx, result, sender, value) in
            guard let ctx = ctx else { return }
            Unmanaged<HIDDriver>.fromOpaque(ctx).takeUnretainedValue().handleInputValue(value)
        }, context)
        
        // CRITICAL: Must use main RunLoop, not CFRunLoopGetCurrent() which may be a background thread
        IOHIDManagerScheduleWithRunLoop(manager!, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let openResult = IOHIDManagerOpen(manager!, IOOptionBits(kIOHIDOptionsTypeNone))
        managerOpenSucceeded = openResult == kIOReturnSuccess
        if openResult == kIOReturnNotPermitted {
            hasInputMonitoringPermission = false
        }
        statusLog("HID manager open result=\(openResult)")
        debugLog("HIDManager opened, result=\(openResult), scheduled on MAIN RunLoop")
    }

    @discardableResult
    func requestInputMonitoringPermission() -> Bool {
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refreshInputMonitoringPermission()
        if granted || hasInputMonitoringPermission {
            restartHIDManagerIfNeeded()
        }
        return granted || hasInputMonitoringPermission
    }

    func refreshInputMonitoringPermission() {
        let previouslyGranted = hasInputMonitoringPermission
        hasInputMonitoringPermission = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        restartHIDManagerIfNeeded(force: hasInputMonitoringPermission && !previouslyGranted)
    }

    func retryGestureControl() {
        gestureControlConfigurationFailed = false
        if featureIndices[HIDPPFeature.reprogControlsV4.rawValue] != nil {
            requestReprogControlCount()
        } else {
            discoverFeature(.reprogControlsV4)
        }
    }
    
    private func handleDeviceConnected(_ device: IOHIDDevice) {
        let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Logitech"
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
        let maxOutput = IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
        
        debugLog("Device=\(name) UsagePage=0x\(String(format:"%04X",usagePage)) Transport='\(transport)' MaxOutput=\(maxOutput)")
        
        // Detect connection type from transport string
        let connType: ConnectionType
        let detectedDeviceIndex: UInt8
        let transportLower = transport.lowercased()
        if transportLower.contains("bluetooth") || transportLower.contains("nearlink") || transportLower == "bluetoothlowenergy" || transportLower == "btle" {
            connType = .bluetooth
            detectedDeviceIndex = 0xFF
        } else if transportLower == "usb" {
            let nameLower = name.lowercased()
            if nameLower.contains("receiver") || nameLower.contains("unifying") || nameLower.contains("bolt") || nameLower.contains("nano") {
                connType = .receiver
                detectedDeviceIndex = 0x01
            } else {
                connType = .usb
                detectedDeviceIndex = 0xFF
            }
        } else {
            // Fallback: check model name
            let nameLower = name.lowercased()
            if nameLower.contains("m720") || nameLower.contains("mx") || nameLower.contains("triathlon") {
                connType = .bluetooth
                detectedDeviceIndex = 0xFF
            } else {
                connType = .unknown
                detectedDeviceIndex = 0xFF
            }
        }
        
        let locationId = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? UInt32 ?? 0
        let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? ""
        
        let uniqueId: String
        if !serial.isEmpty && serial.trimmingCharacters(in: .whitespaces) != "" {
            uniqueId = "\(name)_\(serial)"
        } else {
            uniqueId = "\(name)_\(locationId)"
        }
        
        debugLog("Connection type: \(connType.rawValue) deviceIndex=0x\(String(format:"%02X",detectedDeviceIndex)) uniqueId=\(uniqueId)")
        
        allDevices[uniqueId] = DeviceState(device: device, type: connType, batteryLevel: 0, name: name, uniqueId: uniqueId)
        updatePrimaryDevice()
        
        // HID++ capable interface detection (Only for Logitech 0x046D)
        let vendorId = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let isLogitech = vendorId == 0x046D
        let isHIDPPCapable = isLogitech && ((usagePage >= 0xFF00 && maxOutput >= 7) || (maxOutput >= 20))
        if isHIDPPCapable && activeDevice == nil {
            activeDevice = device
            activeDeviceUniqueId = uniqueId
            deviceIndex = detectedDeviceIndex
            prefersSystemBluetoothBattery = false
            
            // Open the vendor-specific interface
            let openRes = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            activeDeviceOpened = openRes == kIOReturnSuccess
            if openRes == kIOReturnNotPermitted {
                hasInputMonitoringPermission = false
            }
            statusLog("HID++ device open result=\(openRes) productID=\(productID(for: device))")
            debugLog("✅ HID++ interface found! UsagePage=0x\(String(format:"%04X",usagePage)) MaxOutput=\(maxOutput) OpenRes=\(openRes)")
            
            let bufSize = 64
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
            inputReportBuffer = buf
            IOHIDDeviceRegisterInputReportCallback(device, buf, bufSize, { (ctx, result, sender, type, reportId, report, len) in
                Unmanaged<HIDDriver>.fromOpaque(ctx!).takeUnretainedValue().processReport(reportId: reportId, report: report, length: len)
            }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
            
            // Discover device name first (especially important for receivers)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.discoverFeature(.deviceNameType)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.discoverFeature(.batteryLevel)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.discoverFeature(.reprogControlsV4)
            }

        }
    }
    
    private func handleDeviceDisconnected(_ device: IOHIDDevice) {
        if let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String {
            let locationId = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? UInt32 ?? 0
            let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? ""
            let uniqueId: String
            if !serial.isEmpty && serial.trimmingCharacters(in: .whitespaces) != "" {
                uniqueId = "\(name)_\(serial)"
            } else {
                uniqueId = "\(name)_\(locationId)"
            }
            allDevices.removeValue(forKey: uniqueId)
        }
        
        if activeDevice == device {
            if activeDeviceOpened {
                IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            activeDevice = nil
            activeDeviceOpened = false
            activeDeviceUniqueId = ""
            inputReportBuffer?.deallocate()
            inputReportBuffer = nil
            featureIndices.removeAll()
            pendingRequests.removeAll()
            gestureCID = nil
            rawXYGestureCandidate = nil
            divertedGestureCID = nil
            divertedButtonIDs.removeAll()
            isGestureControlReady = false
            gestureControlConfigurationFailed = false
            hasDetectedGestureButton = false
            prefersSystemBluetoothBattery = false
        }
        updatePrimaryDevice()
    }

    private func handleInputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)

        let device = IOHIDElementGetDevice(element)
        let uniqueId = makeUniqueId(for: device)
        let deviceName = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "").lowercased()
        let target = targetDeviceName.lowercased()

        guard !target.isEmpty else { return }
        guard uniqueId.lowercased().contains(target) || deviceName.contains(target) else { return }

        let intValue = IOHIDValueGetIntegerValue(value)
        if intValue != 0, usagePage == 0x07 || usagePage == 0x09 || usagePage == 0x0C {
            debugLog("RAW target=\(uniqueId) usagePage=0x\(String(format: "%02X", usagePage)) usage=\(usage) value=\(intValue)")
        }

        guard let button = mappedButton(usagePage: usagePage, usage: usage) else {
            return
        }

        let isDown = intValue != 0
        debugLog("Mapped raw input target=\(uniqueId) usagePage=0x\(String(format: "%02X", usagePage)) usage=\(usage) -> \(button.label) isDown=\(isDown)")

        DispatchQueue.main.async { [weak self] in
            self?.rawButtonHandler?(button, isDown)
        }
    }

    private func mappedButton(usagePage: UInt32, usage: UInt32) -> MouseButton? {
        if usagePage == 0x09,
           let button = MouseButton(hidUsage: Int(usage)),
           button == .gesture || button == .side3 || button == .side4 {
            return button
        }

        return nil
    }

    private func makeUniqueId(for device: IOHIDDevice) -> String {
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Logitech"
        let locationId = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? UInt32 ?? 0
        let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? ""

        if !serial.isEmpty && serial.trimmingCharacters(in: .whitespaces) != "" {
            return "\(name)_\(serial)"
        }
        return "\(name)_\(locationId)"
    }
    
    private func updatePrimaryDevice() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let previousName = self.deviceName
            
            // Try to find target device first
            var bestMatch: (name: String, state: DeviceState)? = nil
            
            if !self.targetDeviceName.isEmpty {
                if let match = self.allDevices.first(where: { $0.key.lowercased().contains(self.targetDeviceName.lowercased()) }) {
                    bestMatch = (match.key, match.value)
                } else if let match = self.allDevices.first(where: { self.targetDeviceName.lowercased().contains($0.key.lowercased()) }) {
                    bestMatch = (match.key, match.value)
                }
            }
            
            // Fallback to any device
            if bestMatch == nil, let first = self.allDevices.first {
                bestMatch = (first.key, first.value)
            }
            
            if let best = bestMatch {
                self.isConnected = true
                self.deviceName = best.state.name
                self.connectionType = best.state.type
                self.batteryLevel = best.state.batteryLevel
            } else {
                self.isConnected = false
                self.deviceName = "No Device"
                self.connectionType = .unknown
                self.batteryLevel = 0
            }

            if self.deviceName != previousName {
                self.primaryDeviceHandler?(self.deviceName)
            }
        }
    }
    
    func discoverFeature(_ feature: HIDPPFeature) {
        guard activeDevice != nil else {
            debugLog("⚠️ No HID++ interface for \(feature) discovery")
            return
        }
        if feature == .reprogControlsV4 {
            gestureControlConfigurationFailed = false
        }
        let softwareID = allocateSoftwareID()
        let report = HIDPP20.buildGetFeatureIndex(
            feature: feature,
            deviceIndex: deviceIndex,
            softwareID: softwareID
        )
        let hexStr = report.prefix(10).map { String(format:"%02X",$0) }.joined(separator:" ")
        debugLog("→ Discover 0x\(String(format:"%04X",feature.rawValue)): [\(hexStr)]")

        guard send(report, softwareID: softwareID, pending: .discover(feature)) else { return }

        if feature == .reprogControlsV4, deviceIndex == 0xFF {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self,
                      self.featureIndices[feature.rawValue] == nil,
                      self.activeDevice != nil else { return }
                self.deviceIndex = 0x01
                self.discoverFeature(feature)
            }
        }
    }

    private func allocateSoftwareID() -> UInt8 {
        for _ in 0..<15 {
            let candidate = nextSoftwareID
            nextSoftwareID = candidate == 15 ? 1 : candidate + 1
            if pendingRequests[candidate] == nil {
                return candidate
            }
        }
        pendingRequests.removeAll()
        nextSoftwareID = 2
        return 1
    }

    @discardableResult
    private func send(
        _ report: [UInt8],
        softwareID: UInt8,
        pending: PendingHIDPPRequest
    ) -> Bool {
        guard let device = activeDevice, activeDeviceOpened else {
            isGestureControlReady = false
            if pending.isGestureConfiguration && hasInputMonitoringPermission {
                gestureControlConfigurationFailed = true
            }
            return false
        }

        pendingRequests[softwareID] = pending
        let result = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            CFIndex(report[0]),
            report,
            report.count
        )
        guard result == kIOReturnSuccess else {
            pendingRequests.removeValue(forKey: softwareID)
            debugLog("HID++ output report failed: \(result)")
            statusLog("HID++ send failed result=\(result) stage=\(stageName(for: pending))")
            if result == kIOReturnNotPermitted || result == kIOReturnNotOpen {
                hasInputMonitoringPermission = false
            } else if pending.isGestureConfiguration {
                gestureControlConfigurationFailed = true
            }
            return false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let timedOut = self?.pendingRequests.removeValue(forKey: softwareID) else { return }
            statusLog("HID++ request timed out stage=\(self?.stageName(for: timedOut) ?? "unknown")")
            if timedOut.isGestureConfiguration, self?.isGestureControlReady != true {
                self?.gestureControlConfigurationFailed = true
            }
        }
        return true
    }

    private func requestReprogControlCount() {
        guard let featureIndex = featureIndices[HIDPPFeature.reprogControlsV4.rawValue] else { return }
        let softwareID = allocateSoftwareID()
        let report = HIDPP20.buildFeatureRequest(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionID: 0,
            softwareID: softwareID
        )
        send(report, softwareID: softwareID, pending: .reprogCount)
    }

    private func requestNextReprogControlInfo() {
        guard nextReprogControlIndex < reprogControlCount else {
            configureGestureControlIfPossible()
            return
        }
        guard let featureIndex = featureIndices[HIDPPFeature.reprogControlsV4.rawValue] else { return }

        let index = nextReprogControlIndex
        let softwareID = allocateSoftwareID()
        let report = HIDPP20.buildFeatureRequest(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionID: 1,
            softwareID: softwareID,
            parameters: [UInt8(index)]
        )
        if !send(report, softwareID: softwareID, pending: .reprogControlInfo(index)) {
            isGestureControlReady = false
        }
    }

    private func handleReprogControlInfo(_ report: [UInt8], index: Int) {
        guard index == nextReprogControlIndex,
              let info = HIDPPReprogControls.parseControlInfo(from: report) else {
            isGestureControlReady = false
            gestureControlConfigurationFailed = true
            return
        }

        if info.isDivertible && HIDPPReprogControls.gestureCandidates.contains(info.cid) {
            if gestureCID == nil || info.cid == LogitechCID.multiPlatformGestureButton.rawValue {
                gestureCID = info.cid
            }
        } else if info.isDivertible && info.supportsRawXY && rawXYGestureCandidate == nil {
            rawXYGestureCandidate = info.cid
        }
        statusLog(
            "HID++ control index=\(index) cid=0x\(String(format: "%04X", info.cid)) "
                + "flags=0x\(String(format: "%02X", info.flags)) rawXY=\(info.supportsRawXY)"
        )

        nextReprogControlIndex += 1
        requestNextReprogControlInfo()
    }

    private func configureGestureControlIfPossible() {
        guard hasInputMonitoringPermission, gestureActionsEnabled else { return }
        let target = "\(targetDeviceName) \(deviceName)".lowercased()
        guard target.contains("m720") || target.contains("triathlon") else { return }
        guard let featureIndex = featureIndices[HIDPPFeature.reprogControlsV4.rawValue] else { return }
        guard let cid = gestureCID ?? rawXYGestureCandidate else {
            gestureControlConfigurationFailed = true
            return
        }
        statusLog("HID++ diverting gesture cid=0x\(String(format: "%04X", cid))")

        isGestureControlReady = false
        let softwareID = allocateSoftwareID()
        let report = HIDPP20.buildFeatureRequest(
            deviceIndex: deviceIndex,
            featureIndex: featureIndex,
            functionID: 3,
            softwareID: softwareID,
            parameters: HIDPPReprogControls.temporaryDiversionParameters(for: cid)
        )
        if send(report, softwareID: softwareID, pending: .reprogSet(cid)) {
            // Remember the request even if its acknowledgement is lost so the
            // native button behavior can be restored when Whisker exits.
            divertedGestureCID = cid
        }
    }

    private func handleDivertedButtonsEvent(_ report: [UInt8]) {
        guard let gestureCID = divertedGestureCID ?? gestureCID ?? rawXYGestureCandidate else { return }
        let pressed = HIDPPReprogControls.divertedButtonIDs(from: report)
        let wasPressed = divertedButtonIDs.contains(gestureCID)
        let isPressed = pressed.contains(gestureCID)
        divertedButtonIDs = pressed

        guard wasPressed != isPressed else { return }
        if isPressed {
            hasDetectedGestureButton = true
            statusLog("M720 gesture button event detected")
        }
        rawButtonHandler?(.gesture, isPressed)
    }
    
    private func processReport(reportId: UInt32, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        var data = Array(UnsafeBufferPointer(start: report, count: length))
        if data.first != HIDPP20.REPORT_ID_LONG && data.first != HIDPP20.REPORT_ID_SHORT,
           reportId == UInt32(HIDPP20.REPORT_ID_LONG) || reportId == UInt32(HIDPP20.REPORT_ID_SHORT) {
            data.insert(UInt8(reportId), at: 0)
        }
        guard data.count >= 7 else { return }
        
        // M720 pointer movement uses report 0x02. Treating it as HID++ can
        // accidentally consume an unrelated pending request.
        guard data[0] == HIDPP20.REPORT_ID_LONG || data[0] == HIDPP20.REPORT_ID_SHORT else { return }
        
        let rFeatureIdx = data[2]
        let softwareID = data[3] & 0x0F
        
        let hexStr = data.prefix(min(data.count, 20)).map { String(format:"%02X",$0) }.joined(separator:" ")
        debugLog("← [\(hexStr)]")
        
        // Error response
        if rFeatureIdx == 0xFF {
            let failedSoftwareID = data[4] & 0x0F
            let errorCode = data[5]
            debugLog("HID++ error response code=\(errorCode)")
            statusLog("HID++ error response code=\(errorCode) softwareID=\(failedSoftwareID)")
            if let failed = pendingRequests.removeValue(forKey: failedSoftwareID),
               failed.isGestureConfiguration {
                isGestureControlReady = false
                gestureControlConfigurationFailed = true
            }
            return
        }

        if let reprogIndex = featureIndices[HIDPPFeature.reprogControlsV4.rawValue],
           rFeatureIdx == reprogIndex,
           softwareID == 0,
           data[3] >> 4 == 0 {
            handleDivertedButtonsEvent(data)
            return
        }
        
        // Feature Discovery (root index 0x00)
        if rFeatureIdx == 0x00 {
            // IRoot getFeatureIndex response:
            // data[4] = discovered featureIndex (the INDEX, not the feature ID!)
            // data[5] = featureType
            let discoveredIdx = data[4]
            
            guard case let .discover(feature)? = pendingRequests.removeValue(forKey: softwareID) else {
                debugLog("⚠️ Got IRoot response but no pending discovery")
                return
            }
            let requestedFeatureID = feature.rawValue
            
            if discoveredIdx > 0 {
                debugLog("✅ Feature 0x\(String(format:"%04X",requestedFeatureID)) discovered at index \(discoveredIdx)")
                featureIndices[requestedFeatureID] = discoveredIdx
                cancelDuplicateDiscoveries(for: feature)
                if feature == .reprogControlsV4 {
                    statusLog("HID++ 0x1B04 discovered index=\(discoveredIdx)")
                }
                if requestedFeatureID == HIDPPFeature.batteryLevel.rawValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.requestBatteryStatus()
                    }
                } else if requestedFeatureID == HIDPPFeature.deviceNameType.rawValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.requestDeviceName()
                    }
                } else if requestedFeatureID == HIDPPFeature.reprogControlsV4.rawValue {
                    requestReprogControlCount()
                }
            } else {
                debugLog("❌ Feature 0x\(String(format:"%04X",requestedFeatureID)) not supported (index=0)")
                if requestedFeatureID == HIDPPFeature.batteryLevel.rawValue {
                    DispatchQueue.main.async { [weak self] in
                        self?.refreshSystemBluetoothBattery()
                    }
                }
                if requestedFeatureID == HIDPPFeature.reprogControlsV4.rawValue {
                    gestureControlConfigurationFailed = true
                }
            }
            return
        }

        if let pending = pendingRequests.removeValue(forKey: softwareID) {
            switch pending {
            case .reprogCount:
                reprogControlCount = Int(data[4])
                statusLog("HID++ 0x1B04 control count=\(reprogControlCount)")
                nextReprogControlIndex = 0
                gestureCID = nil
                rawXYGestureCandidate = nil
                requestNextReprogControlInfo()
            case .reprogControlInfo(let index):
                handleReprogControlInfo(data, index: index)
            case .reprogSet(let cid):
                // A matched non-error response acknowledges setCidReporting.
                // Some M720 firmware returns a zeroed payload instead of echoing it.
                isGestureControlReady = true
                gestureControlConfigurationFailed = false
                statusLog("HID++ gesture diversion ready=true cid=0x\(String(format: "%04X", cid))")
                debugLog("Gesture control 0x\(String(format: "%04X", cid)) diverted")
            case .discover:
                break
            }
            return
        }
        
        // Battery Level Status (0x1000)
        if let bIdx = featureIndices[HIDPPFeature.batteryLevel.rawValue], rFeatureIdx == bIdx {
            guard let level = HIDPPBattery.percentage(from: data) else { return }
            debugLog("🔋 Battery (0x1000): \(level)%")
            DispatchQueue.main.async {
                guard !self.prefersSystemBluetoothBattery else { return }
                self.updateBatteryLevel(level, source: "0x1000")
            }
            return
        }
        
        // Device Name Response (0x0005)
        if let nIdx = featureIndices[HIDPPFeature.deviceNameType.rawValue], rFeatureIdx == nIdx {
            // Function 0x01 getDeviceName response: data[4..] = UTF-8 name characters
            var nameBytes: [UInt8] = []
            for i in 4..<data.count {
                if data[i] == 0 { break }
                nameBytes.append(data[i])
            }
            if let deviceName = String(bytes: nameBytes, encoding: .utf8), !deviceName.isEmpty {
                debugLog("📛 Device name from HID++: \(deviceName)")
                DispatchQueue.main.async {
                    // Update the name in allDevices for the active HID++ device
                    if !self.activeDeviceUniqueId.isEmpty,
                       var state = self.allDevices[self.activeDeviceUniqueId] {
                        state.name = deviceName
                        self.allDevices[self.activeDeviceUniqueId] = state
                        self.updatePrimaryDevice()
                    }
                }
            }
            return
        }

    }
    
    func requestBatteryStatus() {
        guard let device = activeDevice else { return }
        refreshSystemBluetoothBattery()
        guard let index = featureIndices[HIDPPFeature.batteryLevel.rawValue] else {
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

    private func refreshSystemBluetoothBattery() {
        guard !isSystemBatteryRefreshInFlight,
              !activeDeviceUniqueId.isEmpty,
              let state = allDevices[activeDeviceUniqueId],
              state.type == .bluetooth else { return }

        isSystemBatteryRefreshInFlight = true
        let uniqueId = activeDeviceUniqueId
        let name = state.name
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice

            var level: Int?
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    level = SystemBluetoothBattery.percentage(from: data, matching: name)
                }
            } catch {
                debugLog("System Bluetooth battery query failed: \(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.isSystemBatteryRefreshInFlight = false
                guard self.activeDeviceUniqueId == uniqueId, let level else { return }
                self.prefersSystemBluetoothBattery = true
                self.updateBatteryLevel(level, source: "system-bluetooth")
            }
        }
    }

    private func updateBatteryLevel(_ level: Int, source: String) {
        guard (1...100).contains(level), !activeDeviceUniqueId.isEmpty else { return }
        allDevices[activeDeviceUniqueId]?.batteryLevel = level
        statusLog("HID++ battery level=\(level) source=\(source)")
        updatePrimaryDevice()
    }

    func requestDeviceName() {
        guard let device = activeDevice else { return }
        guard let index = featureIndices[HIDPPFeature.deviceNameType.rawValue] else {
            discoverFeature(.deviceNameType)
            return
        }
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = HIDPP20.REPORT_ID_LONG
        report[1] = deviceIndex
        report[2] = index
        report[3] = 0x10  // function 0x01 (getDeviceName), shifted left 4 bits
        report[4] = 0x00  // charIndex = 0 (start from beginning)
        debugLog("📛 Requesting device name (index=\(index) devIdx=0x\(String(format:"%02X",deviceIndex)))")
        IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), report, report.count)
    }

    private func cancelDuplicateDiscoveries(for feature: HIDPPFeature) {
        let duplicateSoftwareIDs = pendingRequests.compactMap { softwareID, request -> UInt8? in
            if case .discover(let pendingFeature) = request, pendingFeature == feature {
                return softwareID
            }
            return nil
        }
        for softwareID in duplicateSoftwareIDs {
            pendingRequests.removeValue(forKey: softwareID)
        }
    }

    private func isM720(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("m720") || lower.contains("triathlon")
    }

    private func productID(for device: IOHIDDevice) -> Int {
        IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
    }

    private func stageName(for request: PendingHIDPPRequest) -> String {
        switch request {
        case .discover(let feature):
            return String(format: "discover-0x%04X", feature.rawValue)
        case .reprogCount:
            return "reprog-count"
        case .reprogControlInfo(let index):
            return "reprog-control-\(index)"
        case .reprogSet:
            return "reprog-set"
        }
    }

    private func disableGestureDiversion() {
        if let device = activeDevice,
           activeDeviceOpened,
           let cid = divertedGestureCID,
           let featureIndex = featureIndices[HIDPPFeature.reprogControlsV4.rawValue] {
            let report = HIDPP20.buildFeatureRequest(
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                functionID: 3,
                softwareID: 0x0F,
                parameters: HIDPPReprogControls.temporaryDiversionParameters(for: cid, enabled: false)
            )
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                CFIndex(report[0]),
                report,
                report.count
            )
        }

        let staleSoftwareIDs = pendingRequests.compactMap { softwareID, request -> UInt8? in
            if case .reprogSet = request {
                return softwareID
            }
            return nil
        }
        for softwareID in staleSoftwareIDs {
            pendingRequests.removeValue(forKey: softwareID)
        }
        divertedGestureCID = nil
        divertedButtonIDs.removeAll()
        isGestureControlReady = false
        gestureControlConfigurationFailed = false
        hasDetectedGestureButton = false
    }

    private func restartHIDManagerIfNeeded(force: Bool = false) {
        guard hasInputMonitoringPermission,
              manager != nil,
              force || !managerOpenSucceeded || (activeDevice != nil && !activeDeviceOpened) else { return }
        teardownHIDManager()
        setupHIDManager()
    }

    private func teardownHIDManager() {
        disableGestureDiversion()
        if let activeDevice, activeDeviceOpened {
            IOHIDDeviceClose(activeDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        activeDevice = nil
        activeDeviceOpened = false
        activeDeviceUniqueId = ""
        inputReportBuffer?.deallocate()
        inputReportBuffer = nil
        manager = nil
        managerOpenSucceeded = false
        prefersSystemBluetoothBattery = false
        featureIndices.removeAll()
        pendingRequests.removeAll()
        gestureCID = nil
        rawXYGestureCandidate = nil
        divertedGestureCID = nil
        divertedButtonIDs.removeAll()
        isGestureControlReady = false
        gestureControlConfigurationFailed = false
        hasDetectedGestureButton = false
        allDevices.removeAll()
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        teardownHIDManager()
    }
    
}
