import Foundation
import Combine

struct MouseProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var mappings: [Int: String]

    static let defaultGaming = MouseProfile(
        name: "Gaming",
        mappings: [
            3: "Back",
            4: "Forward"
        ]
    )

    static let defaultWork = MouseProfile(
        name: "Work",
        mappings: [
            3: "Mission Control",
            4: "App Exposé"
        ]
    )
}

final class ProfileManager: ObservableObject {
    static let defaultDevice = "M720 Triathlon"

    @Published private(set) var profiles: [MouseProfile] = []
    @Published private(set) var activeProfileID: UUID?
    @Published private(set) var deviceProfiles: [String: UUID] = [:]
    @Published private(set) var lastSelectedDevice = ProfileManager.defaultDevice
    @Published private(set) var lastSaveError: String?

    private static let activeProfileKey = "activeProfileID"
    private static let lastSelectedDeviceKey = "lastSelectedDevice"

    private let savePath: URL
    private let deviceProfilesPath: URL
    private let defaults: UserDefaults

    init(storageDirectory: URL? = nil, defaults: UserDefaults = .standard) {
        let appSupport = storageDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Whisker", isDirectory: true)

        savePath = appSupport.appendingPathComponent("profiles.json")
        deviceProfilesPath = appSupport.appendingPathComponent("deviceProfiles.json")
        self.defaults = defaults

        load()

        if profiles.isEmpty {
            profiles = [.defaultGaming, .defaultWork]
        }

        repairLoadedState()
        save()
    }

    var activeProfile: MouseProfile? {
        profiles.first { $0.id == activeProfileID }
    }

    static func canonicalDeviceKey(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.contains("m720") || lower.contains("triathlon") {
            return "M720 Triathlon"
        }
        if lower.contains("g pro") || lower.contains("gpro") {
            return "G Pro Wireless"
        }
        if lower.contains("atk") || lower.contains("dragonfly") {
            return "ATK Dragonfly A9"
        }
        if lower.contains("mx master") {
            return "Logitech MX Master"
        }
        if lower.contains("mx anywhere") {
            return "Logitech MX Anywhere"
        }

        return trimmed.isEmpty ? defaultDevice : trimmed
    }

    static func hidMatchTerm(for deviceName: String) -> String {
        let canonical = canonicalDeviceKey(deviceName)
        return canonical == "ATK Dragonfly A9" ? "atk" : canonical
    }

    static func isRecognizedDevice(_ deviceName: String) -> Bool {
        let canonical = canonicalDeviceKey(deviceName)
        return [
            "M720 Triathlon",
            "G Pro Wireless",
            "ATK Dragonfly A9",
            "Logitech MX Master",
            "Logitech MX Anywhere"
        ].contains(canonical)
    }

    @discardableResult
    func save() -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let profileData = try encoder.encode(profiles)
            let deviceData = try encoder.encode(deviceProfiles)

            try FileManager.default.createDirectory(
                at: savePath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try profileData.write(to: savePath, options: .atomic)
            try deviceData.write(to: deviceProfilesPath, options: .atomic)

            defaults.set(activeProfileID?.uuidString, forKey: Self.activeProfileKey)
            defaults.set(lastSelectedDevice, forKey: Self.lastSelectedDeviceKey)
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error.localizedDescription
            print("Failed to save profiles: \(error)")
            return false
        }
    }

    func restoreLastProfile(eventManager: EventTapManager) {
        applyProfile(for: lastSelectedDevice, eventManager: eventManager)
    }

    func applyProfile(for deviceName: String, eventManager: EventTapManager) {
        let deviceKey = Self.canonicalDeviceKey(deviceName)
        lastSelectedDevice = deviceKey

        let assignedID = deviceProfiles[deviceKey]
        if let assignedID, containsProfile(assignedID) {
            activeProfileID = assignedID
        } else if let activeProfileID, containsProfile(activeProfileID) {
            deviceProfiles[deviceKey] = activeProfileID
        } else {
            activeProfileID = profiles.first?.id
            deviceProfiles[deviceKey] = activeProfileID
        }

        if let activeProfile {
            eventManager.applyMappings(resolvedMappings(for: activeProfile))
        } else {
            eventManager.resetToDefaults()
        }
        save()
    }

    func selectProfile(_ profileID: UUID, for deviceName: String, eventManager: EventTapManager) {
        guard containsProfile(profileID) else { return }
        let deviceKey = Self.canonicalDeviceKey(deviceName)
        activeProfileID = profileID
        lastSelectedDevice = deviceKey
        deviceProfiles[deviceKey] = profileID
        applyProfile(for: deviceKey, eventManager: eventManager)
    }

    @discardableResult
    func saveMappings(_ mappings: [MouseButton: MouseAction], for deviceName: String? = nil) -> Bool {
        guard let activeProfileID,
              let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else {
            return false
        }

        let deviceKey = Self.canonicalDeviceKey(deviceName ?? lastSelectedDevice)
        profiles[index].mappings = Dictionary(
            uniqueKeysWithValues: mappings.map { ($0.key.rawValue, $0.value.rawValue) }
        )
        lastSelectedDevice = deviceKey
        deviceProfiles[deviceKey] = activeProfileID
        return save()
    }

    @discardableResult
    func addProfile(name: String, copying mappings: [MouseButton: MouseAction]) -> MouseProfile {
        let rawMappings = Dictionary(
            uniqueKeysWithValues: mappings.map { ($0.key.rawValue, $0.value.rawValue) }
        )
        let profile = MouseProfile(name: name, mappings: rawMappings)
        profiles.append(profile)
        save()
        return profile
    }

    func renameProfile(_ profileID: UUID, to name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].name = name
        save()
    }

    func deleteProfile(_ profileID: UUID, eventManager: EventTapManager) {
        guard profiles.count > 1,
              let index = profiles.firstIndex(where: { $0.id == profileID }) else {
            return
        }

        profiles.remove(at: index)
        guard let replacementID = profiles.first?.id else { return }

        let assignedDevices = deviceProfiles.compactMap { device, assignedID in
            assignedID == profileID ? device : nil
        }
        for device in assignedDevices {
            deviceProfiles[device] = replacementID
        }
        if activeProfileID == profileID || !containsProfile(activeProfileID) {
            activeProfileID = deviceProfiles[lastSelectedDevice] ?? replacementID
        }

        applyProfile(for: lastSelectedDevice, eventManager: eventManager)
    }

    private func load() {
        if FileManager.default.fileExists(atPath: savePath.path) {
            do {
                profiles = try JSONDecoder().decode(
                    [MouseProfile].self,
                    from: Data(contentsOf: savePath)
                )
            } catch {
                print("Failed to load profiles: \(error)")
            }
        }

        if FileManager.default.fileExists(atPath: deviceProfilesPath.path) {
            do {
                deviceProfiles = try JSONDecoder().decode(
                    [String: UUID].self,
                    from: Data(contentsOf: deviceProfilesPath)
                )
            } catch {
                print("Failed to load device profiles: \(error)")
            }
        }
    }

    private func repairLoadedState() {
        let validIDs = Set(profiles.map(\.id))
        let exactAssignments = deviceProfiles.filter {
            Self.canonicalDeviceKey($0.key) == $0.key && validIDs.contains($0.value)
        }
        var migrated = exactAssignments

        for (rawDevice, profileID) in deviceProfiles where validIDs.contains(profileID) {
            let canonical = Self.canonicalDeviceKey(rawDevice)
            if migrated[canonical] == nil {
                migrated[canonical] = profileID
            }
        }
        deviceProfiles = migrated

        let savedDevice = defaults.string(forKey: Self.lastSelectedDeviceKey)
        if let savedDevice, !savedDevice.isEmpty {
            lastSelectedDevice = Self.canonicalDeviceKey(savedDevice)
        } else if deviceProfiles[Self.defaultDevice] != nil {
            lastSelectedDevice = Self.defaultDevice
        } else if let firstDevice = deviceProfiles.keys.sorted().first {
            lastSelectedDevice = firstDevice
        }

        let savedActiveID = defaults.string(forKey: Self.activeProfileKey).flatMap(UUID.init(uuidString:))
        let candidates = [deviceProfiles[lastSelectedDevice], savedActiveID, profiles.first?.id]
        activeProfileID = candidates.compactMap { $0 }.first(where: validIDs.contains)

        if let activeProfileID {
            deviceProfiles[lastSelectedDevice] = activeProfileID
        }
    }

    private func containsProfile(_ profileID: UUID?) -> Bool {
        guard let profileID else { return false }
        return profiles.contains { $0.id == profileID }
    }

    private func resolvedMappings(for profile: MouseProfile) -> [MouseButton: MouseAction] {
        Dictionary(uniqueKeysWithValues: MouseButton.allCases.map { button in
            let action = profile.mappings[button.rawValue].flatMap(MouseAction.init(rawValue:))
                ?? button.defaultAction
            return (button, action)
        })
    }
}
