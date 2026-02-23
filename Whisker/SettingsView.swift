import SwiftUI

struct SettingsView: View {
    @ObservedObject var profileManager: ProfileManager
    @Environment(\.dismiss) var dismiss
    @Binding var appLanguage: String
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("profiles")
                    .font(.title3.bold())
                Spacer()
                Button(action: {
                    let newProfile = MouseProfile(name: "Profile \(profileManager.profiles.count + 1)", mappings: [:])
                    profileManager.profiles.append(newProfile)
                    profileManager.save()
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
                ForEach($profileManager.profiles) { $profile in
                    HStack(spacing: 10) {
                        if profileManager.profiles.count > 1 {
                            Button(action: {
                                if let idx = profileManager.profiles.firstIndex(where: { $0.id == profile.id }) {
                                    let wasActive = profile.id == profileManager.activeProfileID
                                    profileManager.profiles.remove(at: idx)
                                    if wasActive {
                                        profileManager.activeProfileID = profileManager.profiles.first?.id
                                    }
                                    profileManager.save()
                                }
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        TextField("name", text: $profile.name)
                            .textFieldStyle(.plain)
                            .onChange(of: profile.name) { _ in
                                profileManager.save()
                            }
                        
                        Spacer()
                        
                        if profile.id == profileManager.activeProfileID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.cyan)
                        } else {
                            Button("useProfile") {
                                profileManager.activeProfileID = profile.id
                                profileManager.save()
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
