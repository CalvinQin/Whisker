import Foundation
import CoreGraphics
import AppKit

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
}

enum MouseButton: Int, Codable, CaseIterable, Identifiable {
    case left = 0
    case right = 1
    case middle = 2
    case side1 = 3
    case side2 = 4
    case gesture = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .left: return "Left Click"
        case .right: return "Right Click"
        case .middle: return "Middle Click"
        case .side1: return "Side Button 1"
        case .side2: return "Side Button 2"
        case .gesture: return "Gesture Button"
        }
    }

    var defaultAction: MouseAction {
        switch self {
        case .left: return .original("Primary Click")
        case .right: return .original("Secondary Click")
        case .middle: return .original("Middle Click")
        case .side1: return .original("Back")
        case .side2: return .original("Forward")
        case .gesture: return .appExpose
        }
    }
}

class EventTapManager: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var hasAccessibilityPermission: Bool = false
    @Published var buttonMappings: [MouseButton: MouseAction] = [:]
    @Published var smoothScrollEnabled: Bool {
        didSet { UserDefaults.standard.set(smoothScrollEnabled, forKey: "smoothScrollEnabled") }
    }


    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init() {
        smoothScrollEnabled = UserDefaults.standard.bool(forKey: "smoothScrollEnabled")
        resetToDefaults()
        checkAccessibilityPermission()
    }

    func resetToDefaults() {
        for button in MouseButton.allCases {
            buttonMappings[button] = button.defaultAction
        }
    }

    func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        guard hasAccessibilityPermission else {
            checkAccessibilityPermission()
            return
        }
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
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
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
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
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
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        DispatchQueue.main.async {
            self.isEnabled = false
        }
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle tap disabled events (system can disable taps under load)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return nil
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

        guard let mouseButton = MouseButton(rawValue: Int(buttonNumber)),
              let action = buttonMappings[mouseButton],
              action != mouseButton.defaultAction else {
            return Unmanaged.passRetained(event)
        }

        let isDown = (type == .otherMouseDown)

        switch action {
        case .original:
            return Unmanaged.passRetained(event)
        case .missionControl:
            if isDown { DispatchQueue.global().async { self.launchApplication("Mission Control", isSystem: true) } }
            return nil
        case .appExpose:
            // F10 is the universal standard for App Exposé in macOS if unmapped natively, or use shortcut
            if isDown { DispatchQueue.global().async { self.performKeyboardShortcut(key: 0x6D, flags: []) } } // F10
            return nil
        case .launchpad:
            if isDown { DispatchQueue.global().async { self.launchApplication("Launchpad", isSystem: true) } }
            return nil
        case .moveLeftSpace:
            if isDown { DispatchQueue.global().async { self.performKeyboardShortcut(key: 0x7B, flags: [.maskControl]) } } // Ctrl+Left
            return nil
        case .moveRightSpace:
            if isDown { DispatchQueue.global().async { self.performKeyboardShortcut(key: 0x7C, flags: [.maskControl]) } } // Ctrl+Right
            return nil
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
            return nil
        case .showDesktop:
            if isDown { DispatchQueue.global().async { self.performKeyboardShortcut(key: 0x67, flags: []) } } // F11
            return nil
        case .copy:
            if isDown { DispatchQueue.global().async { self.performKeyboardShortcut(key: 0x08, flags: [.maskCommand]) } } // ⌘C
            return nil
        case .paste:
            if isDown { DispatchQueue.global().async { self.performKeyboardShortcut(key: 0x09, flags: [.maskCommand]) } } // ⌘V
            return nil
        case .cut:
            if isDown { DispatchQueue.global().async { self.performKeyboardShortcut(key: 0x07, flags: [.maskCommand]) } } // ⌘X
            return nil
        case .undo:
            if isDown { DispatchQueue.global().async { self.performKeyboardShortcut(key: 0x06, flags: [.maskCommand]) } } // ⌘Z
            return nil
        case .redo:
            if isDown { DispatchQueue.global().async { self.performKeyboardShortcut(key: 0x06, flags: [.maskCommand, .maskShift]) } } // ⌘⇧Z
            return nil
        case .customShortcut(let key, let flags):
            if isDown {
                DispatchQueue.global().async {
                    self.performKeyboardShortcut(key: key, flags: CGEventFlags(rawValue: flags))
                }
            }
            return nil
        case .scrollUp:
            if isDown { DispatchQueue.global().async { self.synthesizeScroll(deltaY: 5) } }
            return nil
        case .scrollDown:
            if isDown { DispatchQueue.global().async { self.synthesizeScroll(deltaY: -5) } }
            return nil
        case .none:
            return nil
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
        return Unmanaged.passRetained(newEvent)
    }

    private func synthesizeOtherClick(buttonNumber: Int64, isDown: Bool, location: CGPoint) -> Unmanaged<CGEvent>? {
        let source = CGEventSource(stateID: .hidSystemState)
        let eventType: CGEventType = isDown ? .otherMouseDown : .otherMouseUp
        guard let newEvent = CGEvent(mouseEventSource: source, mouseType: eventType, mouseCursorPosition: location, mouseButton: .center) else {
            return nil
        }
        newEvent.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
        return Unmanaged.passRetained(newEvent)
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
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
            keyDown.flags = flags
            keyUp.flags = flags
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
        }
    }

    private func synthesizeScroll(deltaY: Int32) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let scrollEvent = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: deltaY, wheel2: 0, wheel3: 0) {
            scrollEvent.post(tap: .cgSessionEventTap)
        }
    }

    private func launchApplication(_ name: String, isSystem: Bool = false) {
        let url = isSystem ? URL(fileURLWithPath: "/System/Applications/\(name).app") : nil
        if let appUrl = url {
            NSWorkspace.shared.openApplication(at: appUrl, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } else {
            NSWorkspace.shared.launchApplication(name)
        }
    }
    
    private func handleScrollEvent(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard smoothScrollEnabled else {
            return Unmanaged.passRetained(event)
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
        
        return Unmanaged.passRetained(event)
    }
    private func handleMouseMoveEvent(event: CGEvent) -> Unmanaged<CGEvent>? {
        return Unmanaged.passRetained(event)
    }

    deinit {
        stop()
    }
}
