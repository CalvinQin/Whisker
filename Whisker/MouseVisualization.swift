import SwiftUI

struct MouseCallout: View {
    let button: MouseButton
    let initialTarget: CGPoint
    let initialCallout: CGPoint
    @ObservedObject var eventManager: EventTapManager
    
    @State private var showingRecorder = false
    @State private var targetPoint: CGPoint = .zero
    @State private var calloutPoint: CGPoint = .zero
    @State private var parentSize: CGSize = .zero
    
    @AppStorage("AppLanguage") private var appLanguage = "system"
    
    var currentActionText: String {
        return eventManager.buttonMappings[button]?.displayString() ?? button.defaultAction.displayString()
    }
    
    var body: some View {
        ZStack {
            // Connecting Line
            Path { path in
                path.move(to: calloutPoint)
                // Add a small horizontal elbow
                let elbowX = calloutPoint.x + (targetPoint.x > calloutPoint.x ? 20 : -20)
                path.addLine(to: CGPoint(x: elbowX, y: calloutPoint.y))
                path.addLine(to: targetPoint)
            }
            .stroke(Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
            
            // Target Dot
            Circle()
                .fill(Color.orange)
                .frame(width: 8, height: 8)
                .position(targetPoint)
                .shadow(radius: 2)
            
            // Callout Menu
            Menu {
                // Same logic as MappingMenu
                Section(Localizer.get("Basic Clicks")) {
                    actionButton(for: .original("Primary Click"))
                    actionButton(for: .original("Secondary Click"))
                    actionButton(for: .original("Middle Click"))
                }
                Section(Localizer.get("Navigation")) {
                    actionButton(for: .original("Back"))
                    actionButton(for: .original("Forward"))
                    actionButton(for: .scrollUp)
                    actionButton(for: .scrollDown)
                }
                Section(Localizer.get("OS Controls")) {
                    actionButton(for: .missionControl)
                    actionButton(for: .appExpose)
                    actionButton(for: .showDesktop)
                    actionButton(for: .launchpad)
                }
                Section(Localizer.get("Shortcuts")) {
                    actionButton(for: .copy)
                    actionButton(for: .paste)
                    Button(Localizer.get("Custom Shortcut...")) {
                        showingRecorder = true
                    }
                }
                Section {
                    actionButton(for: .none)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(Localizer.get(button.label))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(currentActionText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .position(calloutPoint)
            .sheet(isPresented: $showingRecorder) {
                VStack {
                    Text("Press Shortcut for \(Localizer.get(button.defaultAction.rawValue))")
                        .padding()
                    KeyboardRecorder(isRecording: $showingRecorder) { code, flags in
                        eventManager.buttonMappings[button] = .customShortcut(key: code, flags: flags)
                        showingRecorder = false
                    }
                    Button("Cancel") { showingRecorder = false }
                        .padding()
                }
                .frame(width: 300, height: 200)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.onAppear {
                    parentSize = geo.size
                    targetPoint = initialTarget
                    calloutPoint = initialCallout
                }
                .onChange(of: geo.size) { newSize in
                    parentSize = newSize
                    targetPoint = initialTarget
                    calloutPoint = initialCallout
                }
            }
        )
    }
    
    @ViewBuilder
    private func actionButton(for action: MouseAction) -> some View {
        Button {
            eventManager.buttonMappings[button] = action
        } label: {
            HStack {
                Text(action.displayString())
                if eventManager.buttonMappings[button] == action {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}

struct MouseVisualization: View {
    let mouseType: String
    @Binding var activeCID: UInt16?
    @Binding var selectedButton: MouseButton?
    @ObservedObject var eventManager: EventTapManager
    
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            
            ZStack {
                let lower = mouseType.lowercased()
                if lower.contains("m720") || lower.contains("triathlon") {
                    m720View(w: w, h: h)
                } else if lower.contains("atk") || lower.contains("dragonfly") {
                    atkView(w: w, h: h)
                } else if lower.contains("g pro") || lower.contains("gpro") || lower.isEmpty {
                    gProView(w: w, h: h)
                } else {
                    gProView(w: w, h: h)
                }
            }
        }
        .frame(minWidth: 320, minHeight: 380)
    }
    
    @ViewBuilder
    func gProView(w: CGFloat, h: CGFloat) -> some View {
        Image("gpw")
            .resizable()
            .scaledToFit()
            .frame(width: w * 0.65)
            .position(x: w / 2, y: h / 2)
            .shadow(color: Color.black.opacity(0.6), radius: 25, x: 0, y: 15)
            .opacity(0.95)
        
        MouseCallout(button: .left, initialTarget: CGPoint(x: w*0.41, y: h*0.39), initialCallout: CGPoint(x: w*0.20, y: h*0.24), eventManager: eventManager)
        MouseCallout(button: .right, initialTarget: CGPoint(x: w*0.59, y: h*0.39), initialCallout: CGPoint(x: w*0.78, y: h*0.24), eventManager: eventManager)
        MouseCallout(button: .middle, initialTarget: CGPoint(x: w*0.50, y: h*0.35), initialCallout: CGPoint(x: w*0.50, y: h*0.12), eventManager: eventManager)
        
        MouseCallout(button: .side2, initialTarget: CGPoint(x: w*0.35, y: h*0.44), initialCallout: CGPoint(x: w*0.13, y: h*0.46), eventManager: eventManager)
        MouseCallout(button: .side1, initialTarget: CGPoint(x: w*0.35, y: h*0.53), initialCallout: CGPoint(x: w*0.13, y: h*0.57), eventManager: eventManager)
        
        MouseCallout(button: .side4, initialTarget: CGPoint(x: w*0.65, y: h*0.45), initialCallout: CGPoint(x: w*0.85, y: h*0.46), eventManager: eventManager)
        MouseCallout(button: .side3, initialTarget: CGPoint(x: w*0.64, y: h*0.54), initialCallout: CGPoint(x: w*0.85, y: h*0.57), eventManager: eventManager)
    }

    @ViewBuilder
    func m720View(w: CGFloat, h: CGFloat) -> some View {
        Image("m720")
            .resizable()
            .scaledToFit()
            .frame(width: w * 0.70) // Normalize for new transparent PNG
            .position(x: w / 2, y: h / 2)
            .shadow(color: Color.black.opacity(0.6), radius: 25, x: 0, y: 15)
            .opacity(0.95)
        
        MouseCallout(button: .left, initialTarget: CGPoint(x: w*0.35, y: h*0.40), initialCallout: CGPoint(x: w*0.14, y: h*0.29), eventManager: eventManager)
        MouseCallout(button: .right, initialTarget: CGPoint(x: w*0.51, y: h*0.36), initialCallout: CGPoint(x: w*0.78, y: h*0.35), eventManager: eventManager)
        MouseCallout(button: .middle, initialTarget: CGPoint(x: w*0.38, y: h*0.36), initialCallout: CGPoint(x: w*0.50, y: h*0.25), eventManager: eventManager)
        
        MouseCallout(button: .side2, initialTarget: CGPoint(x: w*0.32, y: h*0.46), initialCallout: CGPoint(x: w*0.15, y: h*0.47), eventManager: eventManager)
        MouseCallout(button: .side1, initialTarget: CGPoint(x: w*0.37, y: h*0.48), initialCallout: CGPoint(x: w*0.15, y: h*0.59), eventManager: eventManager)
        MouseCallout(button: .gesture, initialTarget: CGPoint(x: w*0.40, y: h*0.61), initialCallout: CGPoint(x: w*0.22, y: h*0.72), eventManager: eventManager)
    }

    @ViewBuilder
    func atkView(w: CGFloat, h: CGFloat) -> some View {
        Image("atk")
            .resizable()
            .scaledToFit()
            .frame(width: w * 0.6) // Closer to GPW baseline
            .position(x: w / 2, y: h / 2)
            .shadow(color: Color.black.opacity(0.6), radius: 25, x: 0, y: 15)
            .opacity(0.95)
        
        MouseCallout(button: .left, initialTarget: CGPoint(x: w*0.42, y: h*0.43), initialCallout: CGPoint(x: w*0.20, y: h*0.25), eventManager: eventManager)
        MouseCallout(button: .right, initialTarget: CGPoint(x: w*0.58, y: h*0.43), initialCallout: CGPoint(x: w*0.75, y: h*0.26), eventManager: eventManager)
        MouseCallout(button: .middle, initialTarget: CGPoint(x: w*0.50, y: h*0.36), initialCallout: CGPoint(x: w*0.45, y: h*0.13), eventManager: eventManager)
        
        MouseCallout(button: .side2, initialTarget: CGPoint(x: w*0.37, y: h*0.46), initialCallout: CGPoint(x: w*0.19, y: h*0.50), eventManager: eventManager)
        MouseCallout(button: .side1, initialTarget: CGPoint(x: w*0.38, y: h*0.53), initialCallout: CGPoint(x: w*0.19, y: h*0.62), eventManager: eventManager)
    }
}
