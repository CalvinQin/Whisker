import Foundation
import SwiftUI
import AppKit

class UpdateManager: ObservableObject {
    @Published var isUpdateAvailable = false
    @Published var latestVersion = ""
    @Published var releaseNotes = ""
    @Published var downloadURL: URL?
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    
    @AppStorage("AutoCheckUpdates") var autoCheckUpdates = true
    
    private let repoOwner = "CalvinQin"
    private let repoName = "Whisker"
    
    private var repoURL: String {
        "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
    }
    
    init() {
        if autoCheckUpdates {
            // Delay auto-check to let the app fully launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.checkForUpdates(manual: false)
            }
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
                   let assets = json["assets"] as? [[String: Any]] {
                    
                    let latestVer = tagName.replacingOccurrences(of: "v", with: "")
                    let currentVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                    
                    // Find the .zip asset
                    let zipAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true })
                    let zipDownloadURL = zipAsset?["browser_download_url"] as? String
                    
                    DispatchQueue.main.async {
                        if self.isNewerVersion(latest: latestVer, current: currentVer) {
                            self.latestVersion = latestVer
                            self.releaseNotes = body
                            if let urlStr = zipDownloadURL, let url = URL(string: urlStr) {
                                self.downloadURL = url
                            }
                            self.isUpdateAvailable = true
                            self.promptForUpdate()
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
        
        let notesPreview = releaseNotes.prefix(300)
        alert.informativeText = Localizer.get("Would you like to update now?") + "\n\n" + Localizer.get("Release Notes:") + "\n" + notesPreview
        alert.alertStyle = .informational
        alert.addButton(withTitle: Localizer.get("Update Now"))
        alert.addButton(withTitle: Localizer.get("Later"))
        
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            downloadAndInstall()
        }
    }
    
    private func promptUpToDate() {
        let currentVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let alert = NSAlert()
        alert.messageText = Localizer.get("You're Up to Date!")
        alert.informativeText = String(format: Localizer.get("Whisker is currently the newest version available."), currentVer)
        alert.alertStyle = .informational
        alert.addButton(withTitle: Localizer.get("OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    
    // MARK: - Self-Update: Download, Extract, Replace, Relaunch
    
    func downloadAndInstall() {
        guard let url = downloadURL else {
            // Fallback: open GitHub releases page
            if let fallback = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest") {
                NSWorkspace.shared.open(fallback)
            }
            return
        }
        
        DispatchQueue.main.async {
            self.isDownloading = true
            self.downloadProgress = 0
        }
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("WhiskerUpdate_\(UUID().uuidString)")
        
        let task = URLSession.shared.downloadTask(with: url) { [weak self] localURL, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isDownloading = false
            }
            
            if let error = error {
                print("Download failed: \(error)")
                DispatchQueue.main.async {
                    self.showError(Localizer.get("Download failed. Please try again."))
                }
                return
            }
            
            guard let localURL = localURL else {
                DispatchQueue.main.async {
                    self.showError(Localizer.get("Download failed. Please try again."))
                }
                return
            }
            
            do {
                // Create temp directory
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                
                // Move downloaded zip to temp
                let zipPath = tempDir.appendingPathComponent("Whisker.zip")
                try FileManager.default.moveItem(at: localURL, to: zipPath)
                
                // Unzip
                let unzipProcess = Process()
                unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzipProcess.arguments = ["-o", zipPath.path, "-d", tempDir.path]
                try unzipProcess.run()
                unzipProcess.waitUntilExit()
                
                guard unzipProcess.terminationStatus == 0 else {
                    throw NSError(domain: "UpdateManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unzip failed"])
                }
                
                // Find the .app in the unzipped directory
                let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
                    throw NSError(domain: "UpdateManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "No .app found in update"])
                }
                
                // Get current app path
                let currentAppPath = Bundle.main.bundlePath
                let currentAppURL = URL(fileURLWithPath: currentAppPath)
                
                // Create a shell script that:
                // 1. Waits for current app to quit
                // 2. Removes old app
                // 3. Moves new app
                // 4. Clears extended attributes 
                // 5. Relaunches
                let scriptContent = """
                #!/bin/bash
                sleep 1
                # Wait for the old process to fully exit
                while pgrep -f "Whisker.app/Contents/MacOS/Whisker" > /dev/null 2>&1; do
                    sleep 0.5
                done
                sleep 0.5
                
                # Replace app
                rm -rf "\(currentAppURL.path)"
                cp -R "\(newApp.path)" "\(currentAppURL.path)"
                
                # Clear extended attributes to avoid codesign issues
                xattr -cr "\(currentAppURL.path)"
                
                # Relaunch
                open "\(currentAppURL.path)"
                
                # Cleanup
                rm -rf "\(tempDir.path)"
                rm -- "$0"
                """
                
                let scriptPath = tempDir.appendingPathComponent("whisker_update.sh")
                try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
                
                // Make script executable
                let chmodProcess = Process()
                chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
                chmodProcess.arguments = ["+x", scriptPath.path]
                try chmodProcess.run()
                chmodProcess.waitUntilExit()
                
                // Run the update script in background
                let shellProcess = Process()
                shellProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
                shellProcess.arguments = [scriptPath.path]
                try shellProcess.run()
                
                // Quit the current app so the script can replace it
                DispatchQueue.main.async {
                    NSApplication.shared.terminate(nil)
                }
                
            } catch {
                print("Update installation failed: \(error)")
                // Cleanup
                try? FileManager.default.removeItem(at: tempDir)
                DispatchQueue.main.async {
                    self.showError(Localizer.get("Update installation failed. Please try again."))
                }
            }
        }
        
        task.resume()
    }
    
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = Localizer.get("Update Failed")
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: Localizer.get("OK"))
        alert.runModal()
    }
}
