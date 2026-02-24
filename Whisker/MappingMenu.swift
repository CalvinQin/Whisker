import SwiftUI

struct MappingMenu: View {
    let button: MouseButton
    @ObservedObject var eventManager: EventTapManager
    @State private var showingRecorder = false
    
    private var currentMapping: MouseAction {
        eventManager.buttonMappings[button] ?? button.defaultAction
    }
    
    private var isCustomShortcutActive: Bool {
        switch currentMapping {
        case .customShortcut(let key, _):
            return key != 0xFFFF
        default:
            return false
        }
    }

    @Environment(\.colorScheme) var colorScheme
    @AppStorage("AppLanguage") private var appLanguage = "system"

    var body: some View {
        VStack(spacing: 0) {
            Text(Localizer.get(button.label))
                .font(.headline)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 4) {
                    
                    // Group 1: Basic Clicks
                    MenuSection(
                        actions: [.original("Primary Click"), .original("Secondary Click"), .original("Middle Click")],
                        currentMapping: currentMapping,
                        button: button,
                        eventManager: eventManager
                    )
                    
                    Divider().padding(.vertical, 4)
                    
                    // Group 2: Navigation
                    MenuSection(
                        actions: [.original("Back"), .original("Forward"), .scrollUp, .scrollDown],
                        currentMapping: currentMapping,
                        button: button,
                        eventManager: eventManager
                    )
                    
                    Divider().padding(.vertical, 4)
                    
                    // Group 3: Mission Control & Spaces
                    MenuSection(
                        actions: [.missionControl, .appExpose, .showDesktop, .launchpad],
                        currentMapping: currentMapping,
                        button: button,
                        eventManager: eventManager
                    )
                    
                    Divider().padding(.vertical, 4)
                    
                    // Group 4: OS Utilities
                    MenuSection(
                        actions: [.moveLeftSpace, .moveRightSpace, .toggleDarkMode],
                        currentMapping: currentMapping,
                        button: button,
                        eventManager: eventManager
                    )
                    
                    Divider().padding(.vertical, 4)
                    
                    // Group 5: Edit Shortcuts
                    MenuSection(
                        actions: [.copy, .paste, .cut, .undo, .redo],
                        currentMapping: currentMapping,
                        button: button,
                        eventManager: eventManager
                    )
                    
                    Divider().padding(.vertical, 4)
                    
                    // Custom Shortcut Item
                    Button(action: {
                        showingRecorder = true
                    }) {
                        HStack {
                            if isCustomShortcutActive {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                            } else {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 12))
                            }
                            Text(Localizer.get("customShortcut"))
                            Spacer()
                            if isCustomShortcutActive {
                                Text(currentMapping.displayString())
                                    .foregroundColor(.secondary)
                                    .font(.caption2)
                                    .opacity(0.8)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isCustomShortcutActive ? Color.orange : Color.clear)
                        .foregroundColor(isCustomShortcutActive ? .white : .primary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    if showingRecorder {
                        KeyboardRecorder(isRecording: $showingRecorder) { code, flags in
                            eventManager.buttonMappings[button] = .customShortcut(key: code, flags: flags)
                            showingRecorder = false
                        }
                        .padding(.vertical, 8)
                    }
                    
                    Divider().padding(.vertical, 4)
                    
                    // Group 5: Disabled
                    MenuSection(
                        actions: [.none],
                        currentMapping: currentMapping,
                        button: button,
                        eventManager: eventManager
                    )
                }
                .padding(8)
            }
        }
        .frame(width: 260, height: 400)
    }
}

struct MenuSection: View {
    let actions: [MouseAction]
    let currentMapping: MouseAction
    let button: MouseButton
    @ObservedObject var eventManager: EventTapManager
    
    var body: some View {
        ForEach(actions) { action in
            let isSelected = currentMapping == action
            
            Button(action: {
                eventManager.buttonMappings[button] = action
            }) {
                HStack {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 16)
                    } else {
                        Spacer().frame(width: 16)
                    }
                    Text(action.displayString())
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
                .foregroundColor(isSelected ? .blue : .primary)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }
}

struct KeyboardRecorder: View {
    @Binding var isRecording: Bool
    var onShortcutRecorded: ((CGKeyCode, UInt64) -> Void)
    
    @State private var monitor: Any?
    @State private var currentKeys: String = ""
    
    @AppStorage("AppLanguage") private var appLanguage = "system"
    
    var body: some View {
        VStack(spacing: 12) {
            if !currentKeys.isEmpty {
                Text(currentKeys)
                    .font(.subheadline.bold())
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
            } else {
                Text(Localizer.get("pressAnyKey"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Button(Localizer.get("stopRecording")) {
                    stopMonitoring()
                    isRecording = false
                }
                .buttonStyle(.plain)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
        .onAppear { startMonitoring() }
        .onDisappear { stopMonitoring() }
    }
    
    private func startMonitoring() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let keyCode = event.keyCode
            
            var parts: [String] = []
            if flags.contains(.control) { parts.append("⌃") }
            if flags.contains(.option) { parts.append("⌥") }
            if flags.contains(.shift) { parts.append("⇧") }
            if flags.contains(.command) { parts.append("⌘") }
            
            if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
                parts.append(chars.uppercased())
            } else {
                parts.append("K\(keyCode)")
            }
            
            currentKeys = parts.joined(separator: "")
            
            var cgFlags: UInt64 = 0
            if flags.contains(.command) { cgFlags |= CGEventFlags.maskCommand.rawValue }
            if flags.contains(.shift) { cgFlags |= CGEventFlags.maskShift.rawValue }
            if flags.contains(.option) { cgFlags |= CGEventFlags.maskAlternate.rawValue }
            if flags.contains(.control) { cgFlags |= CGEventFlags.maskControl.rawValue }
            
            onShortcutRecorded(keyCode, cgFlags)
            return nil
        }
    }
    
    private func stopMonitoring() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
