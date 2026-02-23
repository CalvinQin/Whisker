import Foundation
import IOKit
import IOKit.hid

class HIDManager: ObservableObject {
    private var manager: IOHIDManager?
    
    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(0))
        
        let deviceMatch: [String: Any] = [
            kIOHIDVendorIDKey: 0x046D // Logitech
        ]
        
        IOHIDManagerSetDeviceMatching(manager!, deviceMatch as CFDictionary)
        
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        IOHIDManagerRegisterDeviceMatchingCallback(manager!, { (context, result, sender, device) in
            let this = Unmanaged<HIDManager>.fromOpaque(context!).takeUnretainedValue()
            this.deviceConnected(device)
        }, context)
        
        IOHIDManagerRegisterDeviceRemovalCallback(manager!, { (context, result, sender, device) in
            let this = Unmanaged<HIDManager>.fromOpaque(context!).takeUnretainedValue()
            this.deviceRemoved(device)
        }, context)
        
        IOHIDManagerScheduleWithRunLoop(manager!, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager!, IOOptionBits(0))
    }
    
    private func deviceConnected(_ device: IOHIDDevice) {
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString)
        print("Device Connected: \(String(describing: name))")
    }
    
    private func deviceRemoved(_ device: IOHIDDevice) {
        print("Device Removed")
    }
}
