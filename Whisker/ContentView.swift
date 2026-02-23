import SwiftUI

// MARK: - Main Content View

struct ContentView: View {
    @ObservedObject var driver: HIDDriver
    @ObservedObject var eventManager: EventTapManager
    @ObservedObject var profileManager: ProfileManager
    
    @State private var selectedMouse: String = "M720 Triathlon"
    @State private var activeCID: UInt16? = nil
    @State private var showingSettings = false
    @State private var selectedButtonForMapping: MouseButton? = nil
    @State private var showSaveToast = false
    @State private var selectedTab: Int = 0
    @AppStorage("AppLanguage") private var appLanguage: String = "system"
    
    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()
            
            if !eventManager.hasAccessibilityPermission {
                OnboardingView(eventManager: eventManager)
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(100)
            } else {
                mainContent
                    .transition(.opacity)
            }
        }
        .frame(width: 340, height: 580)
        .onChange(of: driver.deviceName) { newName in
            let lower = newName.lowercased()
            if lower.contains("atk") || lower.contains("dragonfly") {
                selectedMouse = "ATK Dragonfly A9"
            } else if lower.contains("m720") {
                selectedMouse = "M720 Triathlon"
            }
        }
        .onAppear {
            let lower = driver.deviceName.lowercased()
            if lower.contains("atk") || lower.contains("dragonfly") {
                selectedMouse = "ATK Dragonfly A9"
            }
        }
        .animation(.easeInOut(duration: 0.25), value: eventManager.hasAccessibilityPermission)
        .sheet(isPresented: $showingSettings) {
            SettingsView(profileManager: profileManager, appLanguage: $appLanguage)
                .environment(\.locale, localeForLanguage(appLanguage))
        }
        .environment(\.locale, localeForLanguage(appLanguage))
    }
    
    // MARK: - Connection Check
    
    var isSelectedMouseConnected: Bool {
        guard driver.isConnected else { return false }
        let deviceLower = driver.deviceName.lowercased()
        let selectedLower = selectedMouse.lowercased()
        
        if deviceLower.contains("atk") || deviceLower.contains("dragonfly") {
            return selectedLower.contains("atk") || selectedLower.contains("dragonfly")
        }
        
        if selectedLower.contains("m720") && deviceLower.contains("m720") { return true }
        if selectedLower.contains("g pro") && deviceLower.contains("g pro") { return true }
        return deviceLower.contains(selectedLower) || selectedLower.contains(deviceLower)
    }
    
    // MARK: - Main Content
    
    var mainContent: some View {
        VStack(spacing: 0) {
            // ── Header ──
            headerBar
            
            Divider()
            
            // ── Tab Bar ──
            tabBar
            
            Divider()
            
            // ── Content Area ──
            if selectedTab == 0 {
                mouseArea
            } else {
                settingsArea
            }
        }
    }
    
    // MARK: - Header
    
    var headerBar: some View {
        HStack {
            Text("Whisker")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            
            Spacer()
            
            if isSelectedMouseConnected {
                // Connection icons
                HStack(spacing: 4) {
                    if selectedMouse.contains("G Pro") {
                        connectionDot(.usb, icon: "cable.connector")
                        connectionDot(.receiver, icon: "antenna.radiowaves.left.and.right")
                    } else {
                        connectionDot(.receiver, icon: "antenna.radiowaves.left.and.right")
                        connectionDot(.bluetooth, icon: "bluetooth")
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(6)
                
                // Battery
                HStack(spacing: 2) {
                    Image(systemName: batteryIcon)
                        .font(.system(size: 10))
                    Text(driver.batteryLevel > 0 ? "\(driver.batteryLevel)%" : "--%")
                        .font(.system(size: 10, design: .monospaced).bold())
                }
                .foregroundStyle(batteryColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - Tab Bar
    
    var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(icon: "house.fill", index: 0)
            tabButton(icon: "square.grid.2x2", index: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
    
    func tabButton(icon: String, index: Int) -> some View {
        Button(action: { selectedTab = index }) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(selectedTab == index ? .orange : .secondary)
                .frame(width: 36, height: 28)
                .background(selectedTab == index ? Color.orange.opacity(0.1) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Mouse Area (Tab 0)
    
    var mouseArea: some View {
        VStack(spacing: 0) {
            // Mouse model
            HStack {
                Menu {
                    Button("G Pro Wireless") { selectedMouse = "G Pro Wireless" }
                    Button("M720 Triathlon") { selectedMouse = "M720 Triathlon" }
                    Button("ATK Dragonfly A9") { selectedMouse = "ATK Dragonfly A9" }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedMouse)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Smooth scroll toggle
                Toggle(isOn: $eventManager.smoothScrollEnabled) {
                    Image(systemName: eventManager.smoothScrollEnabled ? "water.waves" : "line.3.horizontal")
                        .font(.system(size: 12))
                        .foregroundColor(eventManager.smoothScrollEnabled ? .blue : .secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            // Mouse Visualization
            MouseVisualization(
                mouseType: selectedMouse,
                activeCID: $activeCID,
                selectedButton: $selectedButtonForMapping,
                eventManager: eventManager
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 8)
            
            // Bottom bar
            HStack {
                Text("mouseEnhancement")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: saveAndSync) {
                    HStack(spacing: 4) {
                        Image(systemName: showSaveToast ? "checkmark" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                        Text(showSaveToast ? "savedSuccess" : "saveSync")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(showSaveToast ? .green : .orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(showSaveToast ? Color.green : Color.orange, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: showSaveToast)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.02))
            .overlay(Divider(), alignment: .top)
        }
    }
    
    // MARK: - Settings Area (Tab 1)
    
    var settingsArea: some View {
        VStack(spacing: 12) {
            // Profile selector
            ForEach(profileManager.profiles) { profile in
                HStack {
                    Text(profile.name)
                        .font(.system(size: 13))
                    Spacer()
                    if profile.id == profileManager.activeProfileID {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 14))
                    } else {
                        Button(action: {
                            profileManager.activeProfileID = profile.id
                            profileManager.save()
                        }) {
                            Text("useProfile")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            
            Divider().padding(.horizontal, 16)
            
            // Language
            HStack {
                Text("Language")
                    .font(.system(size: 13))
                Spacer()
                Picker("", selection: $appLanguage) {
                    Text("System").tag("system")
                    Text("EN").tag("en")
                    Text("中文").tag("zh-Hans")
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            .padding(.horizontal, 16)
            
            Divider().padding(.horizontal, 16)
            
            // Manage profiles button
            Button(action: { showingSettings = true }) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                    Text("manageProfiles")
                        .font(.system(size: 12))
                }
                .foregroundColor(.orange)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            
            Spacer()
        }
        .padding(.top, 12)
    }
    
    // MARK: - Connection Dot
    
    @ViewBuilder
    func connectionDot(_ type: ConnectionType, icon: String) -> some View {
        let isActive = type == driver.connectionType
        Group {
            if icon == "bluetooth", let btImg = NSImage(named: NSImage.bluetoothTemplateName) {
                let _ = { btImg.isTemplate = true }()
                Image(nsImage: btImg)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 11)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: isActive ? .bold : .regular))
            }
        }
        .foregroundColor(isActive ?
            (type == .bluetooth ? .blue : type == .usb ? .green : .purple)
            : Color.gray.opacity(0.4))
    }
    
    // MARK: - Battery Helpers
    
    var batteryIcon: String {
        driver.batteryLevel > 75 ? "battery.100" :
        driver.batteryLevel > 50 ? "battery.75" :
        driver.batteryLevel > 20 ? "battery.50" :
        driver.batteryLevel > 0 ? "battery.25" : "battery.0"
    }
    
    var batteryColor: Color {
        driver.batteryLevel == 0 ? .gray :
        driver.batteryLevel > 20 ? .green : .red
    }
    
    // MARK: - Actions
    
    private func saveAndSync() {
        if let index = profileManager.profiles.firstIndex(where: { $0.id == profileManager.activeProfileID }) {
            var newMappings = [Int: String]()
            for (btn, action) in eventManager.buttonMappings {
                newMappings[btn.rawValue] = action.rawValue
            }
            profileManager.profiles[index].mappings = newMappings
        }
        profileManager.save()
        driver.requestBatteryStatus()
        
        withAnimation(.spring()) { showSaveToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showSaveToast = false }
        }
    }
    
    private func localeForLanguage(_ lang: String) -> Locale {
        lang == "system" ? Locale.autoupdatingCurrent : Locale(identifier: lang)
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @ObservedObject var eventManager: EventTapManager
    
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "computermouse.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundStyle(.orange)
                .symbolEffect(.bounce.up.byLayer, options: .repeating)
            
            Text("welcomeTitle")
                .font(.title3.bold())
            
            Text("welcomeSubtitle")
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            
            VStack(alignment: .leading, spacing: 8) {
                stepRow("1.circle.fill", "onboardingStep1")
                stepRow("2.circle.fill", "onboardingStep2")
                stepRow("3.circle.fill", "onboardingStep3")
                stepRow("4.circle.fill", "onboardingStepInput")
                
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 10))
                        .padding(.top, 2)
                    Text("onboardingStep4")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(10)
            
            VStack(spacing: 8) {
                Button(action: { openAccessibilitySettings() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.raised.fill")
                        Text("openSettingsBtn")
                    }
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                
                Button(action: { openInputMonitoringSettings() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "keyboard.badge.eye")
                        Text("inputMonitoringBtn")
                    }
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            
            Button("checkPermissionBtn") {
                eventManager.checkAccessibilityPermission()
                if eventManager.hasAccessibilityPermission { eventManager.start() }
            }
            .font(.caption)
            .foregroundColor(.orange)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func stepRow(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(.orange).font(.system(size: 12))
            Text(text).font(.system(size: 12))
        }
    }
    
    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            eventManager.checkAccessibilityPermission()
            if eventManager.hasAccessibilityPermission { eventManager.start() }
        }
    }
    
    private func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
