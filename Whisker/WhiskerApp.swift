import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: "hideDockIcon") {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

@main
struct WhiskerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var driver = HIDDriver()
    @StateObject private var eventManager = EventTapManager()
    @StateObject private var profileManager = ProfileManager()
    
    @State private var isWindowVisible = true

    var body: some Scene {
        WindowGroup(id: "main-window") {
            ContentView(driver: driver, eventManager: eventManager, profileManager: profileManager)
                .onAppear {
                    eventManager.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        
        MenuBarExtra {
            WhiskerMenu(driver: driver, eventManager: eventManager, profileManager: profileManager)
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

struct WhiskerMenu: View {
    @ObservedObject var driver: HIDDriver
    @ObservedObject var eventManager: EventTapManager
    @ObservedObject var profileManager: ProfileManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
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
                openWindow(id: "main-window")
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows {
                    if window.identifier?.rawValue == "main-window" {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
            }
            
            Button("Quit Whisker") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
