import SwiftUI

struct SettingsView: View {
    @ObservedObject var profileManager: ProfileManager
    @ObservedObject var eventManager: EventTapManager
    let deviceName: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("profiles")
                    .font(.title3.bold())
                Spacer()
                Button(action: {
                    profileManager.addProfile(
                        name: "Profile \(profileManager.profiles.count + 1)",
                        copying: eventManager.buttonMappings
                    )
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(
                            LinearGradient(colors: [.purple, .cyan], startPoint: .leading, endPoint: .trailing)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            // Profile List
            List {
                ForEach(profileManager.profiles) { profile in
                    HStack(spacing: 10) {
                        if profileManager.profiles.count > 1 {
                            Button(action: {
                                profileManager.deleteProfile(profile.id, eventManager: eventManager)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        TextField(
                            "name",
                            text: Binding(
                                get: {
                                    profileManager.profiles.first(where: { $0.id == profile.id })?.name
                                        ?? profile.name
                                },
                                set: { profileManager.renameProfile(profile.id, to: $0) }
                            )
                        )
                            .textFieldStyle(.plain)
                        
                        Spacer()
                        
                        if profile.id == profileManager.activeProfileID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.cyan)
                        } else {
                            Button("useProfile") {
                                profileManager.selectProfile(
                                    profile.id,
                                    for: deviceName,
                                    eventManager: eventManager
                                )
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Divider()
            
            Button("done") { dismiss() }
                .padding()
        }
        .frame(width: 380, height: 440)
    }
}
