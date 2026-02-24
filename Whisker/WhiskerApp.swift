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
    @StateObject private var updateManager = UpdateManager()
    
    @AppStorage("AppLanguage") private var appLanguage = "system"
    @State private var isWindowVisible = true

    var body: some Scene {
        WindowGroup(id: "main-window") {
            ContentView(driver: driver, eventManager: eventManager, profileManager: profileManager, updateManager: updateManager)
                .environment(\.locale, localeForLanguage(appLanguage))
                .onAppear {
                    eventManager.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        
        MenuBarExtra {
            WhiskerMenu(driver: driver, eventManager: eventManager, profileManager: profileManager, updateManager: updateManager)
                .environment(\.locale, localeForLanguage(appLanguage))
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
    
    // MARK: - Helpers
    private func localeForLanguage(_ lang: String) -> Locale {
        lang == "system" ? Locale.autoupdatingCurrent : Locale(identifier: lang)
    }
}

struct WhiskerMenu: View {
    @ObservedObject var driver: HIDDriver
    @ObservedObject var eventManager: EventTapManager
    @ObservedObject var profileManager: ProfileManager
    @ObservedObject var updateManager: UpdateManager
    @Environment(\.openWindow) private var openWindow

    /// Map raw IOKit product name to a friendly display name
    private func friendlyDeviceName(_ rawName: String) -> String {
        let lower = rawName.lowercased()
        if lower.contains("m720") || lower.contains("triathlon") { return "Logitech M720 Triathlon" }
        if lower.contains("g pro") || lower.contains("gpro") { return "Logitech G Pro Wireless" }
        if lower.contains("atk") || lower.contains("dragonfly") { return "ATK Dragonfly A9" }
        if lower.contains("mx master") { return "Logitech MX Master" }
        if lower.contains("mx anywhere") { return "Logitech MX Anywhere" }
        return rawName
    }
    
    var body: some View {
        VStack {
            Text("Whisker").bold()
            Text("\(Localizer.get("Device:")) \(friendlyDeviceName(driver.deviceName))")
                .font(.caption)
            
            Divider()
            
            if driver.isConnected {
                Text("\(Localizer.get("Connection:")) \(Localizer.get(driver.connectionType.rawValue))")
                    .foregroundColor(.secondary)
                
                Text("\(Localizer.get("Battery:")) \(driver.batteryLevel)%")
                    .foregroundColor(driver.batteryLevel > 20 ? .primary : .red)
            }
            
            Divider()
            
            Menu(Localizer.get("Quick Profiles")) {
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
            
            Toggle(Localizer.get("Smooth Scrolling"), isOn: $eventManager.smoothScrollEnabled)
            
            Divider()
            
            Button(Localizer.get("Open Control Center")) {
                openWindow(id: "main-window")
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows {
                    if window.identifier?.rawValue == "main-window" {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
            }
            
            Button(Localizer.get("Check for Updates...")) {
                updateManager.checkForUpdates(manual: true)
            }
            
            Button(Localizer.get("Quit Whisker")) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

// MARK: - Dynamic Bundle Localization
struct Localizer {
    static var bundle: Bundle {
        let appLanguage = UserDefaults.standard.string(forKey: "AppLanguage") ?? "system"
        if appLanguage == "system" {
            return .main
        }
        guard let path = Bundle.main.path(forResource: appLanguage, ofType: "lproj"),
              let specificBundle = Bundle(path: path) else {
            return .main
        }
        return specificBundle
    }

    static func get(_ key: String) -> String {
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
