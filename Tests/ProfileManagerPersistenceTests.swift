import Foundation

enum MouseAction: Hashable {
    case original(String)
    case missionControl
    case appExpose
    case copy
    case paste
    case none

    init?(rawValue: String) {
        switch rawValue {
        case "Primary Click": self = .original("Primary Click")
        case "Secondary Click": self = .original("Secondary Click")
        case "Middle Click": self = .original("Middle Click")
        case "Back": self = .original("Back")
        case "Forward": self = .original("Forward")
        case "Mission Control": self = .missionControl
        case "App Exposé": self = .appExpose
        case "Copy": self = .copy
        case "Paste": self = .paste
        case "Disabled": self = .none
        default: return nil
        }
    }

    var rawValue: String {
        switch self {
        case .original(let name): return name
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .none: return "Disabled"
        }
    }
}

enum MouseButton: Int, CaseIterable, Hashable {
    case left = 0
    case right = 1
    case middle = 2
    case side1 = 3
    case side2 = 4
    case gesture = 5
    case side3 = 6
    case side4 = 7

    var defaultAction: MouseAction {
        switch self {
        case .left: return .original("Primary Click")
        case .right: return .original("Secondary Click")
        case .middle: return .original("Middle Click")
        case .side1: return .original("Back")
        case .side2: return .original("Forward")
        case .gesture: return .appExpose
        case .side3, .side4: return .none
        }
    }
}

final class EventTapManager {
    private(set) var buttonMappings: [MouseButton: MouseAction] = [:]

    func applyMappings(_ mappings: [MouseButton: MouseAction]) {
        buttonMappings = mappings
    }

    func resetToDefaults() {
        buttonMappings = Dictionary(uniqueKeysWithValues: MouseButton.allCases.map { ($0, $0.defaultAction) })
    }
}

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard condition() else {
        fatalError("\(message) (\(file):\(line))")
    }
}

@main
struct ProfileManagerPersistenceTests {
    static func main() throws {
        let fileManager = FileManager.default
        let storage = fileManager.temporaryDirectory
            .appendingPathComponent("WhiskerProfileTests-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "WhiskerProfileTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated defaults")
        }
        defer {
            try? fileManager.removeItem(at: storage)
            defaults.removePersistentDomain(forName: suiteName)
        }

        try fileManager.createDirectory(at: storage, withIntermediateDirectories: true)
        let gaming = MouseProfile(name: "Gaming", mappings: [3: "Back", 4: "Forward", 5: "Copy"])
        let work = MouseProfile(name: "Work", mappings: [3: "Mission Control", 4: "App Exposé"])
        let encoder = JSONEncoder()
        try encoder.encode([gaming, work]).write(to: storage.appendingPathComponent("profiles.json"))
        try encoder.encode(["Logitech M720 Triathlon_SERIAL": gaming.id])
            .write(to: storage.appendingPathComponent("deviceProfiles.json"))
        defaults.set("Logitech M720 Triathlon_SERIAL", forKey: "lastSelectedDevice")
        defaults.set(gaming.id.uuidString, forKey: "activeProfileID")

        let firstLaunch = ProfileManager(storageDirectory: storage, defaults: defaults)
        expect(firstLaunch.lastSelectedDevice == "M720 Triathlon", "Device key was not canonicalized")
        expect(firstLaunch.deviceProfiles["M720 Triathlon"] == gaming.id, "Device assignment was not migrated")
        let firstEvents = EventTapManager()
        firstLaunch.restoreLastProfile(eventManager: firstEvents)
        expect(firstEvents.buttonMappings[.gesture] == .copy, "Saved gesture mapping was not restored")

        firstLaunch.selectProfile(work.id, for: "M720 Triathlon", eventManager: firstEvents)
        firstEvents.applyMappings(firstEvents.buttonMappings.merging([.gesture: .paste]) { _, new in new })
        expect(firstLaunch.saveMappings(firstEvents.buttonMappings), "Updated mappings were not saved")

        let restarted = ProfileManager(storageDirectory: storage, defaults: defaults)
        let restartedEvents = EventTapManager()
        restarted.restoreLastProfile(eventManager: restartedEvents)
        expect(restarted.activeProfileID == work.id, "Active profile was not restored after restart")
        expect(restartedEvents.buttonMappings[.gesture] == .paste, "Updated gesture action was not restored")

        restarted.deleteProfile(work.id, eventManager: restartedEvents)
        expect(restarted.activeProfileID == gaming.id, "Deleting the active profile did not select a replacement")
        expect(restarted.deviceProfiles["M720 Triathlon"] == gaming.id, "Stale device assignment survived deletion")
        expect(restartedEvents.buttonMappings[.gesture] == .copy, "Replacement profile was not applied")

        print("ProfileManagerPersistenceTests passed")
    }
}
