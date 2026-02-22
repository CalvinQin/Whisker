import SwiftUI

@main
struct VibeMouseApp: App {
    @State private var currentNumber: String = "1"

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        MenuBarExtra("VibeMouse", systemImage: "mouse.fill") {
            Button("Open VibeMouse") {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows {
                    if window.title == "VibeMouse" {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
            }
            Divider()
            Button("Profile: Gaming") {}
            Button("Profile: Work") {}
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
