import SwiftUI
import ServiceManagement

// MARK: - Main Content View

struct ContentView: View {
    @ObservedObject var driver: HIDDriver
    @ObservedObject var eventManager: EventTapManager
    @ObservedObject var profileManager: ProfileManager
    @ObservedObject var updateManager: UpdateManager
    
    @State private var selectedMouse: String
    @State private var activeCID: UInt16? = nil
    @State private var showingSettings = false
    @State private var selectedButtonForMapping: MouseButton? = nil
    @State private var showSaveToast = false
    @State private var showingInfo = false
    @State private var selectedTab: Int = 0
    @State private var launchAtLogin: Bool
    @State private var settingsErrorMessage: String?
    @AppStorage("AppLanguage") private var appLanguage: String = "system"
    @AppStorage("hideDockIcon") private var hideDockIcon: Bool = false
    @AppStorage("AutoCheckUpdates") private var autoCheckUpdates: Bool = true

    init(
        driver: HIDDriver,
        eventManager: EventTapManager,
        profileManager: ProfileManager,
        updateManager: UpdateManager
    ) {
        self.driver = driver
        self.eventManager = eventManager
        self.profileManager = profileManager
        self.updateManager = updateManager
        _selectedMouse = State(initialValue: profileManager.lastSelectedDevice)
        _launchAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled)
    }
    
    var currentDeviceName: String {
        let rawName = driver.connectedDevices[selectedMouse]?.name ?? selectedMouse
        return friendlyDeviceName(rawName)
    }

    private var selectedDeviceProfileKey: String {
        let rawName = driver.connectedDevices[selectedMouse]?.name ?? selectedMouse
        return ProfileManager.canonicalDeviceKey(rawName)
    }
    
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
        ZStack {
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()
            
            if !eventManager.hasAccessibilityPermission {
                OnboardingView(eventManager: eventManager, driver: driver)
            } else {
                mainContent
                    .transition(.opacity)
            }
        }
        .frame(width: 460, height: 620)
        .onChange(of: driver.deviceName) { _, newName in
            if ProfileManager.isRecognizedDevice(newName) {
                let canonical = ProfileManager.canonicalDeviceKey(newName)
                if selectedDeviceProfileKey != canonical {
                    selectedMouse = canonical
                }
            }
        }
        .onChange(of: selectedMouse) { _, newSelection in
            driver.targetDeviceName = ProfileManager.hidMatchTerm(for: newSelection)
            let rawName = driver.connectedDevices[newSelection]?.name ?? newSelection
            profileManager.applyProfile(for: rawName, eventManager: eventManager)
        }
        .onAppear {
            driver.targetDeviceName = ProfileManager.hidMatchTerm(for: selectedMouse)
            profileManager.applyProfile(for: selectedDeviceProfileKey, eventManager: eventManager)
            eventManager.start()
            driver.gestureActionsEnabled = eventManager.hasAccessibilityPermission
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            DockIconController.apply(hidden: hideDockIcon)
        }
        .onChange(of: hideDockIcon) { _, newValue in
            DockIconController.apply(hidden: newValue, activateWhenShown: true)
        }
        .onChange(of: profileManager.lastSaveError) { _, newValue in
            if let newValue {
                settingsErrorMessage = newValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            eventManager.checkAccessibilityPermission(prompt: false)
            eventManager.start()
            driver.gestureActionsEnabled = eventManager.hasAccessibilityPermission
            driver.refreshInputMonitoringPermission()
            launchAtLogin = SMAppService.mainApp.status == .enabled
            DockIconController.apply(hidden: hideDockIcon)
        }
        .animation(.easeInOut(duration: 0.25), value: eventManager.hasAccessibilityPermission)
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                profileManager: profileManager,
                eventManager: eventManager,
                deviceName: selectedDeviceProfileKey
            )
                .environment(\.locale, localeForLanguage(appLanguage))
        }
        .alert(
            Localizer.get("Settings Update Failed"),
            isPresented: Binding(
                get: { settingsErrorMessage != nil },
                set: { if !$0 { settingsErrorMessage = nil } }
            )
        ) {
            Button(Localizer.get("OK"), role: .cancel) {}
        } message: {
            Text(settingsErrorMessage ?? "")
        }
        .environment(\.locale, localeForLanguage(appLanguage))
    }
    
    // MARK: - Connection Check
    
    var isSelectedMouseConnected: Bool {
        guard driver.isConnected else { return false }
        let deviceLower = driver.deviceName.lowercased()
        let selectedLower = currentDeviceName.lowercased()
        
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
            } else if selectedTab == 1 {
                settingsArea // which is actually the Profiles area currently
            } else {
                systemSettingsArea
            }
        }
    }
    
    // MARK: - Header
    
    var headerBar: some View {
        HStack {
            Text("Whisker")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            
            Button(action: { showingInfo.toggle() }) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingInfo, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Localizer.get("Supported Devices:"))
                        .font(.headline)
                    Text("• Logitech G Pro Wireless")
                    Text("• Logitech M720 Triathlon")
                    Text("• ATK Dragonfly A9")
                }
                .padding()
                .frame(width: 220)
            }
            
            Spacer()
            
            if isSelectedMouseConnected {
                // Connection icons
                HStack(spacing: 4) {
                    if currentDeviceName.contains("G Pro") {
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
                .background(Color.primary.opacity(0.08))
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
            tabButton(icon: "gearshape.fill", index: 2)
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
                    Section(Localizer.get("Connected Devices")) {
                        if driver.connectedDevices.isEmpty {
                            Text(Localizer.get("No Devices Connected"))
                        } else {
                            ForEach(Array(driver.connectedDevices.keys).sorted(), id: \.self) { uniqueId in
                                if let state = driver.connectedDevices[uniqueId] {
                                    Button {
                                        selectedMouse = uniqueId
                                    } label: {
                                        HStack {
                                            Text(friendlyDeviceName(state.name))
                                            Image(systemName: state.type.iconName)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Section(Localizer.get("Preview Supported Models")) {
                        Button("G Pro Wireless") { selectedMouse = "G Pro Wireless" }
                        Button("M720 Triathlon") { selectedMouse = "M720 Triathlon" }
                        Button("ATK Dragonfly A9") { selectedMouse = "ATK Dragonfly A9" }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(currentDeviceName)
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
                HStack(spacing: 6) {
                    Text("smoothScrolling")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Toggle("", isOn: $eventManager.smoothScrollEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if !driver.hasInputMonitoringPermission {
                inputMonitoringBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            } else if driver.gestureControlConfigurationFailed,
                      currentDeviceName.lowercased().contains("m720"),
                      isSelectedMouseConnected {
                gestureControlFailureBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            } else if driver.isGestureControlReady,
                      currentDeviceName.lowercased().contains("m720"),
                      isSelectedMouseConnected {
                gestureControlReadyBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
            
            // Mouse Visualization
            MouseVisualization(
                mouseType: currentDeviceName,
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
    
    var settingsArea: some View {
        VStack(spacing: 12) {
            // Header for Profiles
            HStack {
                Text("profiles")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { showingSettings = true }) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            // Profile selector
            ForEach(profileManager.profiles) { profile in
                HStack {
                    Text(profile.name)
                        .font(.system(size: 13, weight: profile.id == profileManager.activeProfileID ? .bold : .regular))
                    Spacer()
                    if profile.id == profileManager.activeProfileID {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 14))
                    } else {
                        Button(action: {
                            profileManager.selectProfile(
                                profile.id,
                                for: selectedDeviceProfileKey,
                                eventManager: eventManager
                            )
                        }) {
                            Text("useProfile")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(profile.id == profileManager.activeProfileID ? Color.orange.opacity(0.1) : Color.clear)
                .cornerRadius(6)
            }
            
            Spacer()
        }
        .padding(.top, 4)
    }
    
    // MARK: - System Settings Area (Tab 2)
    
    var systemSettingsArea: some View {
        VStack(spacing: 24) {
            // Language Setting
            VStack(alignment: .leading, spacing: 12) {
                Text("Language")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Picker("", selection: $appLanguage) {
                    Text("System").tag("system")
                    Text("EN").tag("en")
                    Text("中文").tag("zh-Hans")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            
            // Startup & Launch Settings
            VStack(alignment: .leading, spacing: 16) {
                Text("systemBehavior")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    
                HStack {
                    Text("launchAtLogin")
                        .font(.system(size: 14))
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { launchAtLogin },
                            set: updateLaunchAtLogin
                        )
                    )
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                
                Divider()
                
                HStack {
                    Text("hideDockIcon")
                        .font(.system(size: 14))
                    Spacer()
                    Toggle("", isOn: $hideDockIcon)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                
                Divider()
                
                HStack {
                    Text(Localizer.get("Auto Check for Updates"))
                        .font(.system(size: 14))
                    Spacer()
                    Toggle("", isOn: $autoCheckUpdates)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: autoCheckUpdates) { _, newValue in
                            updateManager.autoCheckUpdates = newValue
                        }
                }
                
                Button(action: {
                    updateManager.checkForUpdates(manual: true)
                }) {
                    HStack {
                        Spacer()
                        Text(Localizer.get("Check for Updates Now"))
                        Spacer()
                    }
                }
                .padding(.top, 8)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            
            Spacer()

        }
        .padding(16)
    }
    
    var inputMonitoringBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
            Text(Localizer.get("Input Monitoring is required for the M720 gesture button."))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button(Localizer.get("Enable")) {
                if !driver.requestInputMonitoringPermission() {
                    openInputMonitoringSettings()
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    var gestureControlFailureBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(Localizer.get("M720 gesture button could not be initialized."))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button(Localizer.get("Retry")) {
                driver.retryGestureControl()
            }
            .font(.system(size: 10, weight: .semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    var gestureControlReadyBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: driver.hasDetectedGestureButton ? "checkmark.circle.fill" : "shield.checkered")
                .foregroundStyle(.green)
            Text(Localizer.get(
                driver.hasDetectedGestureButton
                    ? "M720 gesture button detected."
                    : "M720 gesture button is ready."
            ))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
        }
        .padding(8)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        let didSave = profileManager.saveMappings(
            eventManager.buttonMappings,
            for: selectedDeviceProfileKey
        )
        guard didSave else { return }
        driver.requestBatteryStatus()
        
        withAnimation(.spring()) { showSaveToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showSaveToast = false }
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin {
                settingsErrorMessage = Localizer.get("Allow Whisker in System Settings > General > Login Items.")
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            settingsErrorMessage = error.localizedDescription
        }
    }

    private func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func localeForLanguage(_ lang: String) -> Locale {
        lang == "system" ? Locale.autoupdatingCurrent : Locale(identifier: lang)
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @ObservedObject var eventManager: EventTapManager
    @ObservedObject var driver: HIDDriver
    
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
                driver.gestureActionsEnabled = eventManager.hasAccessibilityPermission
                driver.refreshInputMonitoringPermission()
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
            driver.gestureActionsEnabled = eventManager.hasAccessibilityPermission
            if eventManager.hasAccessibilityPermission { eventManager.start() }
        }
    }
    
    private func openInputMonitoringSettings() {
        driver.requestInputMonitoringPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
