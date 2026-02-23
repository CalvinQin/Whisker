import Foundation

struct MouseProfile: Codable, Identifiable {
    var id = UUID()
    var name: String
    var mappings: [Int: String] // MouseButton.rawValue -> MouseAction.rawValue
    
    static let defaultGaming = MouseProfile(
        name: "Gaming",
        mappings: [
            3: MouseAction.original("Back").rawValue,
            4: MouseAction.original("Forward").rawValue
        ]
    )
    
    static let defaultWork = MouseProfile(
        name: "Work",
        mappings: [
            3: MouseAction.missionControl.rawValue,
            4: MouseAction.appExpose.rawValue
        ]
    )
}

class ProfileManager: ObservableObject {
    @Published var profiles: [MouseProfile] = []
    @Published var activeProfileID: UUID?
    @Published var deviceProfiles: [String: UUID] = [:]
    
    private let savePath: URL
    private let deviceProfilesPath: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let whiskerDir = appSupport.appendingPathComponent("Whisker")
        savePath = whiskerDir.appendingPathComponent("profiles.json")
        deviceProfilesPath = whiskerDir.appendingPathComponent("deviceProfiles.json")
        
        load()
        
        if profiles.isEmpty {
            profiles = [.defaultGaming, .defaultWork]
            activeProfileID = profiles.first?.id
            save()
        }
    }
    
    func save() {
        do {
            let data = try JSONEncoder().encode(profiles)
            let deviceData = try JSONEncoder().encode(deviceProfiles)
            try FileManager.default.createDirectory(at: savePath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: savePath)
            try deviceData.write(to: deviceProfilesPath)
        } catch {
            print("Failed to save profiles: \(error)")
        }
    }
    
    func load() {
        if FileManager.default.fileExists(atPath: savePath.path) {
            do {
                let data = try Data(contentsOf: savePath)
                profiles = try JSONDecoder().decode([MouseProfile].self, from: data)
                activeProfileID = profiles.first?.id
            } catch {
                print("Failed to load profiles: \(error)")
            }
        }
        
        if FileManager.default.fileExists(atPath: deviceProfilesPath.path) {
            do {
                let data = try Data(contentsOf: deviceProfilesPath)
                deviceProfiles = try JSONDecoder().decode([String: UUID].self, from: data)
            } catch {
                print("Failed to load device profiles: \(error)")
            }
        }
    }
    
    var activeProfile: MouseProfile? {
        profiles.first { $0.id == activeProfileID }
    }
    
    func applyProfile(for deviceName: String, eventManager: EventTapManager) {
        let profileId = deviceProfiles[deviceName] ?? profiles.first?.id
        activeProfileID = profileId
        deviceProfiles[deviceName] = profileId
        save()
        
        if let active = activeProfile {
            for button in MouseButton.allCases {
                 if let actionStr = active.mappings[button.rawValue],
                    let action = MouseAction(rawValue: actionStr) {
                     eventManager.buttonMappings[button] = action
                 } else {
                     eventManager.buttonMappings[button] = button.defaultAction
                 }
            }
        }
    }
}
