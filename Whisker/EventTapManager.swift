import Foundation
import CoreGraphics
import AppKit
import os

private let eventTapLogger = Logger(subsystem: "com.haoqi.whisker", category: "EventTap")
private func debugLog(_ msg: String) {
#if DEBUG
    eventTapLogger.debug("\(msg, privacy: .public)")
#endif
}


enum MouseAction: Hashable, Codable, Equatable, Identifiable {
    case original(String)
    case missionControl
    case appExpose
    case launchpad
    case showDesktop
    case moveLeftSpace
    case moveRightSpace
    case toggleDarkMode
    case copy
    case paste
    case cut
    case undo
    case redo
    case customShortcut(key: CGKeyCode, flags: UInt64)
    case scrollUp
    case scrollDown
    case none
    
    static var allCases: [MouseAction] {
        [
            .original("Primary Click"),
            .original("Secondary Click"),
            .original("Middle Click"),
            .original("Back"),
            .original("Forward"),
            .missionControl,
            .appExpose,
            .launchpad,
            .showDesktop,
            .moveLeftSpace,
            .moveRightSpace,
            .toggleDarkMode,
            .copy,
            .paste,
            .cut,
            .undo,
            .redo,
            .scrollUp,
            .scrollDown,
            .none
        ]
    }
    
    // Legacy RawValue-like initializer bridging for backward compatibility with old profiles
    init?(rawValue: String) {
        switch rawValue {
        case "Primary Click": self = .original("Primary Click")
        case "Secondary Click": self = .original("Secondary Click")
        case "Middle Click": self = .original("Middle Click")
        case "Back": self = .original("Back")
        case "Forward": self = .original("Forward")
        case "Mission Control": self = .missionControl
        case "App Exposé": self = .appExpose
        case "Launchpad": self = .launchpad
        case "Show Desktop": self = .showDesktop
        case "Move Left a Space": self = .moveLeftSpace
        case "Move Right a Space": self = .moveRightSpace
        case "Toggle Dark Mode": self = .toggleDarkMode
        case "Copy": self = .copy
        case "Paste": self = .paste
        case "Cut": self = .cut
        case "Undo": self = .undo
        case "Redo": self = .redo
        case "Scroll Up": self = .scrollUp
        case "Scroll Down": self = .scrollDown
        case "Disabled": self = .none
        default:
            if rawValue.starts(with: "Custom:") {
                let parts = rawValue.split(separator: ":")
                if parts.count == 3, 
                   let key = UInt16(parts[1]), 
                   let flags = UInt64(parts[2]) {
                    self = .customShortcut(key: key, flags: flags)
                    return
                }
            }
            return nil
        }
    }
    
    var rawValue: String {
        switch self {
        case .original(let name): return name
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .launchpad: return "Launchpad"
        case .showDesktop: return "Show Desktop"
        case .moveLeftSpace: return "Move Left a Space"
        case .moveRightSpace: return "Move Right a Space"
        case .toggleDarkMode: return "Toggle Dark Mode"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .cut: return "Cut"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .scrollUp: return "Scroll Up"
        case .scrollDown: return "Scroll Down"
        case .customShortcut(let key, let flags): return "Custom:\(key):\(flags)"
        case .none: return "Disabled"
        }
    }

    var id: String { rawValue }
    
    func displayString() -> String {
        switch self {
        case .customShortcut(let key, let flags):
            return "\(MouseAction.stringFor(flags: flags))\(MouseAction.stringFor(keyCode: key))"
        case .none:
            return Localizer.get("Disabled")
        default:
            return Localizer.get(rawValue)
        }
    }
    
    static func stringFor(keyCode: CGKeyCode) -> String {
        let keyMap: [CGKeyCode: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return keyMap[keyCode] ?? "Key \(keyCode)"
    }

    static func stringFor(flags: UInt64) -> String {
        let cgFlags = CGEventFlags(rawValue: flags)
        var parts: [String] = []
        if cgFlags.contains(.maskCommand) { parts.append("⌘") }
        if cgFlags.contains(.maskShift) { parts.append("⇧") }
        if cgFlags.contains(.maskAlternate) { parts.append("⌥") }
        if cgFlags.contains(.maskControl) { parts.append("⌃") }
        return parts.joined()
    }
}

enum MouseButton: Int, Codable, CaseIterable, Identifiable {
    case left = 0
    case right = 1
    case middle = 2
    case side1 = 3
    case side2 = 4
    case gesture = 5
    case side3 = 6
    case side4 = 7

    var id: Int { rawValue }

    init?(hidUsage: Int) {
        switch hidUsage {
        case 1: self = .left
        case 2: self = .right
        case 3: self = .middle
        case 4: self = .side1
        case 5: self = .side2
        case 6: self = .gesture
        case 7: self = .side3
        case 8: self = .side4
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .left: return "L"
        case .right: return "R"
        case .middle: return "Mid"
        case .side1: return "S1"
        case .side2: return "S2"
        case .side3: return "S3"
        case .side4: return "S4"
        case .gesture: return "GB"
        }
    }

    var defaultAction: MouseAction {
        switch self {
        case .left: return .original("Primary Click")
        case .right: return .original("Secondary Click")
        case .middle: return .original("Middle Click")
        case .side1: return .original("Back")
        case .side2: return .original("Forward")
        case .side3: return .none
        case .side4: return .none
        case .gesture: return .appExpose
        }
    }
}

class EventTapManager: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var hasAccessibilityPermission: Bool = false
    @Published private(set) var buttonMappings: [MouseButton: MouseAction] = [:]
    @Published var smoothScrollEnabled: Bool {
        didSet { UserDefaults.standard.set(smoothScrollEnabled, forKey: "smoothScrollEnabled") }
    }

    var mappingChangeHandler: (([MouseButton: MouseAction]) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init() {
        smoothScrollEnabled = UserDefaults.standard.bool(forKey: "smoothScrollEnabled")
        resetToDefaults()
        checkAccessibilityPermission(prompt: false)
    }

    func resetToDefaults() {
        applyMappings(Dictionary(uniqueKeysWithValues: MouseButton.allCases.map { ($0, $0.defaultAction) }))
    }

    func applyMappings(_ mappings: [MouseButton: MouseAction]) {
        buttonMappings = mappings
    }

    func setMapping(_ action: MouseAction, for button: MouseButton) {
        guard buttonMappings[button] != action else { return }
        buttonMappings[button] = action
        mappingChangeHandler?(buttonMappings)
    }

    @discardableResult
    func checkAccessibilityPermission(prompt: Bool = true) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
        return hasAccessibilityPermission
    }

    func start() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.start() }
            return
        }

        if !hasAccessibilityPermission {
            checkAccessibilityPermission(prompt: false)
        }
        guard hasAccessibilityPermission else { return }
        guard eventTap == nil else { return }

        let buttonMask: CGEventMask = (
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)
        )
        let moveMask: CGEventMask = (
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue)
        )
        let eventMask = buttonMask | moveMask

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleEvent(proxy: proxy, type: type, event: event)
        }

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            print("Failed to create event tap. Check accessibility permissions.")
            hasAccessibilityPermission = false
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            DispatchQueue.main.async {
                self.isEnabled = true
            }
            print("Event tap started successfully")
        }
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        DispatchQueue.main.async {
            self.isEnabled = false
        }
    }

    func handleRawButtonEvent(_ button: MouseButton, isDown: Bool) {
        guard let action = buttonMappings[button] else { return }
        guard button == .gesture || action != button.defaultAction else { return }

        executeAction(action, isDown: isDown)
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle tap disabled events (system can disable taps under load)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return nil
        }

        // Isolate from Trackpad (Subtype 0 is standard mouse, 3 is trackpad, etc.)
        let subtype = event.getIntegerValueField(.mouseEventSubtype)
        guard subtype == 0 else {
            return Unmanaged.passUnretained(event)
        }
        
        // Handle scroll wheel events for smooth scrolling
        if type == .scrollWheel {
            return handleScrollEvent(event: event)
        }
        
        // Handle mouse move for software sensitivity
        if type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged {
            return handleMouseMoveEvent(event: event)
        }
        
        
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        if type == .otherMouseDown || type == .leftMouseDown || type == .rightMouseDown {
            debugLog("TAP: Mouse Button Down, ButtonNumber=\(buttonNumber)")
        }

        // Guard to ignore events if the user set it to its "original" mapping,
        // so we don't accidentally swallow them and synthesize left clicks.
        guard let mouseButton = MouseButton(rawValue: Int(buttonNumber)),
              let action = buttonMappings[mouseButton],
              action != mouseButton.defaultAction else {
            return Unmanaged.passUnretained(event)
        }

        // At this point we are INTERCEPTING a button. 
        let isDown = (type == .otherMouseDown || type == .leftMouseDown || type == .rightMouseDown)
        
        if case .original(let name) = action {
            if name == "Primary Click" {
                event.type = isDown ? .leftMouseDown : .leftMouseUp
                event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
            } else if name == "Secondary Click" {
                event.type = isDown ? .rightMouseDown : .rightMouseUp
                event.setIntegerValueField(.mouseEventButtonNumber, value: 1)
            } else if name == "Middle Click" {
                event.type = isDown ? .otherMouseDown : .otherMouseUp
                event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            } else if name == "Back" {
                event.type = isDown ? .otherMouseDown : .otherMouseUp
                event.setIntegerValueField(.mouseEventButtonNumber, value: 3)
            } else if name == "Forward" {
                event.type = isDown ? .otherMouseDown : .otherMouseUp
                event.setIntegerValueField(.mouseEventButtonNumber, value: 4)
            }
            return Unmanaged.passUnretained(event)
        }
        
        // Execute the custom action
        executeAction(action, isDown: isDown)
        
        // Swallow the original hardware button event 
        return nil
    }
    
    private func executeAction(_ action: MouseAction, isDown: Bool) {
        switch action {
        case .original:
            break
        case .missionControl:
            if isDown { launchSystemApplication("Mission Control") }
        case .appExpose:
            // F10 is the universal standard for App Exposé in macOS if unmapped natively, or use shortcut
            if isDown { DispatchQueue.global().async { self.performKeyboardShortcut(key: 0x6D, flags: []) } } // F10
        case .launchpad:
            if isDown { launchSystemApplication("Launchpad") }
        case .moveLeftSpace:
            if isDown { DispatchQueue.global().async { self.performKeyboardShortcut(key: 0x7B, flags: [.maskControl]) } } // Ctrl+Left
        case .moveRightSpace:
            if isDown { DispatchQueue.global().async { self.performKeyboardShortcut(key: 0x7C, flags: [.maskControl]) } } // Ctrl+Right
        case .toggleDarkMode:
            if isDown {
                DispatchQueue.global().async {
                    let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
                    var error: NSDictionary?
                    if let appleScript = NSAppleScript(source: script) {
                        appleScript.executeAndReturnError(&error)
                    }
                }
            }
        case .showDesktop:
            if isDown { DispatchQueue.global().async { self.performKeyboardShortcut(key: 0x67, flags: []) } } // F11
        case .copy:
            if isDown { DispatchQueue.global().async { self.performKeyboardShortcut(key: 0x08, flags: [.maskCommand]) } } // ⌘C
        case .paste:
            if isDown { DispatchQueue.global().async { self.performKeyboardShortcut(key: 0x09, flags: [.maskCommand]) } } // ⌘V
        case .cut:
            if isDown { DispatchQueue.global().async { self.performKeyboardShortcut(key: 0x07, flags: [.maskCommand]) } } // ⌘X
        case .undo:
            if isDown { DispatchQueue.global().async { self.performKeyboardShortcut(key: 0x06, flags: [.maskCommand]) } } // ⌘Z
        case .redo:
            if isDown { DispatchQueue.global().async { self.performKeyboardShortcut(key: 0x06, flags: [.maskCommand, .maskShift]) } } // ⌘⇧Z
        case .customShortcut(let key, let flags):
            if isDown {
                DispatchQueue.global().async {
                    self.performKeyboardShortcut(key: key, flags: CGEventFlags(rawValue: flags))
                }
            }
        case .scrollUp:
            if isDown { DispatchQueue.global().async { self.synthesizeScroll(deltaY: 5) } }
        case .scrollDown:
            if isDown { DispatchQueue.global().async { self.synthesizeScroll(deltaY: -5) } }
        case .none:
            break
        }
    }

    private func synthesizeClick(button: CGMouseButton, isDown: Bool, location: CGPoint) -> Unmanaged<CGEvent>? {
        let source = CGEventSource(stateID: .hidSystemState)
        let eventType: CGEventType = isDown
            ? (button == .left ? .leftMouseDown : .rightMouseDown)
            : (button == .left ? .leftMouseUp : .rightMouseUp)
        guard let newEvent = CGEvent(mouseEventSource: source, mouseType: eventType, mouseCursorPosition: location, mouseButton: button) else {
            return nil
        }
        return Unmanaged.passUnretained(newEvent)
    }

    private func synthesizeOtherClick(buttonNumber: Int64, isDown: Bool, location: CGPoint) -> Unmanaged<CGEvent>? {
        let source = CGEventSource(stateID: .hidSystemState)
        let eventType: CGEventType = isDown ? .otherMouseDown : .otherMouseUp
        guard let newEvent = CGEvent(mouseEventSource: source, mouseType: eventType, mouseCursorPosition: location, mouseButton: .center) else {
            return nil
        }
        newEvent.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
        return Unmanaged.passUnretained(newEvent)
    }

    private func synthesizeKeyPressAsync(key: CGKeyCode, flags: CGEventFlags, isDown: Bool, location: CGPoint) {
        guard let keyEvent = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: isDown) else {
            return
        }
        keyEvent.flags = flags
        keyEvent.post(tap: .cgSessionEventTap)
    }

    private func synthesizeKeyPress(key: CGKeyCode, flags: CGEventFlags, isDown: Bool, location: CGPoint) -> Unmanaged<CGEvent>? {
        guard let keyEvent = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: isDown) else {
            return nil
        }
        keyEvent.flags = flags
        keyEvent.post(tap: .cgSessionEventTap)
        return nil
    }

    private func performKeyboardShortcut(key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // 1. Press modifiers
        if let flagsDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
            flagsDown.type = .flagsChanged
            flagsDown.flags = flags
            flagsDown.post(tap: .cgSessionEventTap)
        }
        
        // 2. Press key
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true) {
            keyDown.flags = flags
            keyDown.post(tap: .cgSessionEventTap)
        }
        
        // 3. Release key
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
            keyUp.flags = flags
            keyUp.post(tap: .cgSessionEventTap)
        }
        
        // 4. Release modifiers
        if let flagsUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
            flagsUp.type = .flagsChanged
            flagsUp.flags = [] // Clear flags
            flagsUp.post(tap: .cgSessionEventTap)
        }
    }

    private func synthesizeScroll(deltaY: Int32) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let scrollEvent = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: deltaY, wheel2: 0, wheel3: 0) {
            scrollEvent.post(tap: .cgSessionEventTap)
        }
    }

    private func launchSystemApplication(_ name: String) {
        let appURL = URL(fileURLWithPath: "/System/Applications/\(name).app")
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
    }
    
    private func handleScrollEvent(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard smoothScrollEnabled else {
            return Unmanaged.passUnretained(event)
        }
        
        // Get the discrete scroll delta (line-based)
        let deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let deltaX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        
        // Convert to smooth pixel scrolling:
        // - Set isContinuous flag to make it pixel-based
        // - Multiply delta for smoother, larger scroll steps
        let smoothMultiplier: Int64 = 8
        
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: deltaY * smoothMultiplier)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: deltaX * smoothMultiplier)
        // Keep the fixed-point fields in sync
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: deltaY * smoothMultiplier * 65536 / 10)
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2, value: deltaX * smoothMultiplier * 65536 / 10)
        
        return Unmanaged.passUnretained(event)
    }

    private func handleMouseMoveEvent(event: CGEvent) -> Unmanaged<CGEvent>? {
        return Unmanaged.passUnretained(event)
    }

    deinit {
        stop()
    }
}
