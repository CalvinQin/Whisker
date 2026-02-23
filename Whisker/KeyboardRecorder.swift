import SwiftUI
import AppKit

struct KeyboardRecorder: View {
    @Binding var isRecording: Bool
    var onShortcutRecorded: ((CGKeyCode, UInt64) -> Void)
    
    @State private var monitor: Any?
    @State private var currentKeys: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard")
                .font(.system(size: 40))
                .foregroundColor(.blue)
            
            Text("pressAnyKey")
                .font(.headline)
            
            if !currentKeys.isEmpty {
                Text(currentKeys)
                    .font(.title2.bold())
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
            
            Button("stopRecording") {
                stopMonitoring()
                isRecording = false
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(40)
        .frame(minWidth: 300, minHeight: 200)
        .onAppear {
            startMonitoring()
        }
        .onDisappear {
            stopMonitoring()
        }
    }
    
    private func startMonitoring() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let keyCode = event.keyCode
            
            // Format string for display
            var parts: [String] = []
            if flags.contains(.command) { parts.append("⌘") }
            if flags.contains(.shift) { parts.append("⇧") }
            if flags.contains(.option) { parts.append("⌥") }
            if flags.contains(.control) { parts.append("⌃") }
            
            if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
                parts.append(chars.uppercased())
            } else {
                parts.append("Key \(keyCode)")
            }
            
            currentKeys = parts.joined(separator: " + ")
            
            // Convert to CGEventFlags
            var cgFlags: UInt64 = 0
            if flags.contains(.command) { cgFlags |= CGEventFlags.maskCommand.rawValue }
            if flags.contains(.shift) { cgFlags |= CGEventFlags.maskShift.rawValue }
            if flags.contains(.option) { cgFlags |= CGEventFlags.maskAlternate.rawValue }
            if flags.contains(.control) { cgFlags |= CGEventFlags.maskControl.rawValue }
            
            // Trigger callback
            onShortcutRecorded(keyCode, cgFlags)
            
            // Small delay to let user see it
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isRecording = false
            }
            
            return nil // Consume event
        }
    }
    
    private func stopMonitoring() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
