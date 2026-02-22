import SwiftUI

struct ContentView: View {
    @StateObject var driver = HIDDriver()
    @State private var selectedMouse: String = "G Pro Wireless"
    @State private var activeCID: UInt16? = nil
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                header
                
                HStack(alignment: .top, spacing: 30) {
                    VStack {
                        MouseVisualization(mouseType: selectedMouse, activeCID: $activeCID)
                            .padding(.bottom, 20)
                        
                        Picker("", selection: $selectedMouse) {
                            Text("G Pro Wireless").tag("G Pro Wireless")
                            Text("M720 Triathlon").tag("M720 Triathlon")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                    .frame(width: 300)
                    .vibeCardStyle()
                    
                    rightPanel
                }
                .padding()
                
                footer
            }
        }
        .frame(width: 850, height: 550)
    }
    
    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("VibeMouse")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.linearGradient(colors: [.primary, .blue], startPoint: .leading, endPoint: .trailing))
                
                HStack {
                    Circle()
                        .fill(driver.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(driver.isConnected ? driver.deviceName : "No hardware detected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            
            if driver.isConnected {
                batteryIndicator
            }
        }
        .padding(30)
    }
    
    var batteryIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: driver.batteryLevel > 20 ? "battery.75" : "battery.25")
                .foregroundStyle(driver.batteryLevel > 20 ? .green : .red)
            Text("\(driver.batteryLevel)%")
                .font(.system(.body, design: .monospaced))
                .fontWeight(.bold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 1))
    }
    
    var rightPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Button Customization")
                .font(.headline)
            
            ScrollView {
                VStack(spacing: 12) {
                    InteractiveMappingRow(cid: 0x0001, label: "Left Click", action: "Primary Click", activeCID: $activeCID)
                    InteractiveMappingRow(cid: 0x0002, label: "Right Click", action: "Secondary Click", activeCID: $activeCID)
                    InteractiveMappingRow(cid: 0x0003, label: "Middle Click", action: "Mission Control", activeCID: $activeCID)
                    InteractiveMappingRow(cid: 0x0004, label: "Side Button 1", action: "Back", activeCID: $activeCID)
                    InteractiveMappingRow(cid: 0x0005, label: "Side Button 2", action: "Forward", activeCID: $activeCID)
                    
                    if selectedMouse == "M720 Triathlon" {
                        InteractiveMappingRow(cid: 0x00C3, label: "Gesture Button", action: "App Expose", activeCID: $activeCID)
                    }
                }
            }
            
            Divider()
            
            sensitivityControl
        }
        .padding()
        .vibeCardStyle()
    }
    
    var sensitivityControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DPI Sensitivity")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("1600 DPI")
                    .font(.subheadline.bold())
            }
            Slider(value: .constant(1600), in: 400...16000, step: 100)
                .accentColor(.blue)
        }
    }
    
    var footer: some View {
        HStack {
            Text("Overnight Build 02.23")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button(action: { driver.requestBatteryStatus() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            
            Button("Apply Profiles") {
                // Sync logic
            }
            .buttonStyle(LiquidButton())
        }
        .padding(25)
    }
}

struct InteractiveMappingRow: View {
    let cid: UInt16
    let label: String
    let action: String
    @Binding var activeCID: UInt16?
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(action)
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(6)
        }
        .padding(12)
        .background(activeCID == cid ? Color.blue.opacity(0.1) : Color.primary.opacity(0.03))
        .cornerRadius(10)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                activeCID = hovering ? cid : nil
            }
        }
    }
}
