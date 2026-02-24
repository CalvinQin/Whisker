import Foundation
import SwiftUI
import AppKit

class UpdateManager: ObservableObject {
    @Published var isUpdateAvailable = false
    @Published var latestVersion = ""
    @Published var releaseNotes = ""
    @Published var downloadURL: URL?
    
    @AppStorage("AutoCheckUpdates") var autoCheckUpdates = true
    
    private let repoURL = "https://api.github.com/repos/CalvinQin/Whisker/releases/latest"
    
    init() {
        if autoCheckUpdates {
            checkForUpdates(manual: false)
        }
    }
    
    func checkForUpdates(manual: Bool = false) {
        guard let url = URL(string: repoURL) else { return }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error checking for updates: \(error)")
                self.handleManualCheckResult(manual: manual, success: false)
                return
            }
            
            guard let data = data else {
                self.handleManualCheckResult(manual: manual, success: false)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let tagName = json["tag_name"] as? String,
                   let body = json["body"] as? String,
                   let htmlUrlString = json["html_url"] as? String,
                   let htmlUrl = URL(string: htmlUrlString) {
                    
                    let latestVer = tagName.replacingOccurrences(of: "v", with: "")
                    let currentVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                    
                    DispatchQueue.main.async {
                        if self.isNewerVersion(latest: latestVer, current: currentVer) {
                            self.latestVersion = latestVer
                            self.releaseNotes = body
                            self.downloadURL = htmlUrl
                            self.isUpdateAvailable = true
                            
                            if manual {
                                self.promptForUpdate()
                            } else {
                                // For auto checks, we might want to prompt or just show a badge.
                                // For now, we prompt if autoCheckUpdates is true and an update is found on launch.
                                self.promptForUpdate() // Or alternatively, let the user trigger it from the menu
                            }
                        } else {
                            if manual {
                                self.promptUpToDate()
                            }
                        }
                    }
                }
            } catch {
                print("Error parsing update JSON: \(error)")
                self.handleManualCheckResult(manual: manual, success: false)
            }
        }.resume()
    }
    
    private func handleManualCheckResult(manual: Bool, success: Bool) {
        if manual && !success {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = Localizer.get("Update Check Failed")
                alert.informativeText = Localizer.get("Unable to check for updates. Please check your network connection.")
                alert.alertStyle = .warning
                alert.addButton(withTitle: Localizer.get("OK"))
                alert.runModal()
            }
        }
    }
    
    private func isNewerVersion(latest: String, current: String) -> Bool {
        return latest.compare(current, options: .numeric) == .orderedDescending
    }
    
    func promptForUpdate() {
        let alert = NSAlert()
        alert.messageText = String(format: Localizer.get("Update Available Format"), latestVersion)
        alert.informativeText = Localizer.get("Would you like to download it now?") + "\n\n" + Localizer.get("Release Notes:") + "\n" + releaseNotes
        alert.alertStyle = .informational
        alert.addButton(withTitle: Localizer.get("Download"))
        alert.addButton(withTitle: Localizer.get("Later"))
        
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            downloadAndInstall()
        }
    }
    
    private func promptUpToDate() {
        let alert = NSAlert()
        alert.messageText = Localizer.get("You're Up to Date!")
        alert.informativeText = String(format: Localizer.get("Whisker is currently the newest version available."), Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
        alert.alertStyle = .informational
        alert.addButton(withTitle: Localizer.get("OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    
    func downloadAndInstall() {
        if let url = downloadURL {
            NSWorkspace.shared.open(url)
        }
    }
}
