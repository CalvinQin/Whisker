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
    
    private let savePath: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        savePath = appSupport.appendingPathComponent("Whisker").appendingPathComponent("profiles.json")
        
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
            try FileManager.default.createDirectory(at: savePath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: savePath)
        } catch {
            print("Failed to save profiles: \(error)")
        }
    }
    
    func load() {
        guard FileManager.default.fileExists(atPath: savePath.path) else { return }
        do {
            let data = try Data(contentsOf: savePath)
            profiles = try JSONDecoder().decode([MouseProfile].self, from: data)
            activeProfileID = profiles.first?.id
        } catch {
            print("Failed to load profiles: \(error)")
        }
    }
    
    var activeProfile: MouseProfile? {
        profiles.first { $0.id == activeProfileID }
    }
}
