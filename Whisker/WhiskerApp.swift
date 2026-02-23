import SwiftUI

@main
struct WhiskerApp: App {
    @StateObject private var driver = HIDDriver()
    @StateObject private var eventManager = EventTapManager()
    @StateObject private var profileManager = ProfileManager()
    
    @State private var isWindowVisible = true

    var body: some Scene {
        WindowGroup {
            ContentView(driver: driver, eventManager: eventManager, profileManager: profileManager)
                .onAppear {
                    eventManager.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        MenuBarExtra {
            VStack {
                Text("Whisker").bold()
                Text("Device: \(driver.deviceName)")
                    .font(.caption)
                
                Divider()
                
                if driver.isConnected {
                    Text("Connection: \(driver.connectionType.rawValue)")
                        .foregroundColor(.secondary)
                    
                    Text("Battery: \(driver.batteryLevel)%")
                        .foregroundColor(driver.batteryLevel > 20 ? .primary : .red)
                }
                
                Divider()
                
                Menu("Quick Profiles") {
                    ForEach(profileManager.profiles) { profile in
                        Button(action: {
                            let target = driver.targetDeviceName.isEmpty ? driver.deviceName : driver.targetDeviceName
                            profileManager.deviceProfiles[target] = profile.id
                            profileManager.applyProfile(for: target, eventManager: eventManager)
                        }) {
                            HStack {
                                Text(profile.name)
                                if profile.id == profileManager.activeProfileID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                Divider()
                
                Toggle("Smooth Scrolling", isOn: $eventManager.smoothScrollEnabled)
                
                Divider()
                
                Button("Open Control Center") {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                
                Button("Quit Whisker") {
                    NSApplication.shared.terminate(nil)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "computermouse.fill")
                if driver.isConnected {
                    Text("\(driver.batteryLevel)%")
                        .font(.system(size: 11, design: .monospaced))
                }
            }
        }
    }
}
