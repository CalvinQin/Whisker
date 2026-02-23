import SwiftUI

struct MouseClickRegion: View {
    let points: [CGPoint]
    let c1s: [CGPoint?]
    let c2s: [CGPoint?]
    var isClosed: Bool = false
    
    var body: some View {
        Path { path in
            if points.isEmpty { return }
            path.move(to: points[0])
            for i in 1..<points.count {
                if let c1 = c1s[i], let c2 = c2s[i] {
                    path.addCurve(to: points[i], control1: c1, control2: c2)
                } else if let c1 = c1s[i] {
                    path.addQuadCurve(to: points[i], control: c1)
                } else {
                    path.addLine(to: points[i])
                }
            }
            if isClosed {
                path.closeSubpath()
            }
        }
        .fill(Color.clear)
        .contentShape(
            Path { path in
                if points.isEmpty { return }
                path.move(to: points[0])
                for i in 1..<points.count {
                    if let c1 = c1s[i], let c2 = c2s[i] {
                        path.addCurve(to: points[i], control1: c1, control2: c2)
                    } else if let c1 = c1s[i] {
                        path.addQuadCurve(to: points[i], control: c1)
                    } else {
                        path.addLine(to: points[i])
                    }
                }
                if isClosed {
                    path.closeSubpath()
                }
            }
        )
        .overlay(
            Path { path in
                if points.isEmpty { return }
                path.move(to: points[0])
                for i in 1..<points.count {
                    if let c1 = c1s[i], let c2 = c2s[i] {
                        path.addCurve(to: points[i], control1: c1, control2: c2)
                    } else if let c1 = c1s[i] {
                        path.addQuadCurve(to: points[i], control: c1)
                    } else {
                        path.addLine(to: points[i])
                    }
                }
                if isClosed {
                    path.closeSubpath()
                }
            }
            .stroke(Color.primary.opacity(0.15), lineWidth: 1.5)
        )
    }
}

struct ButtonBadge: View {
    let label: String
    let button: MouseButton
    let position: CGPoint
    @Binding var selectedButton: MouseButton?
    @ObservedObject var eventManager: EventTapManager
    
    var body: some View {
        Button(action: {
            selectedButton = button
        }) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(selectedButton == button ? Color.blue : Color.orange)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .position(position)
        .popover(isPresented: Binding(
            get: { selectedButton == button },
            set: { if !$0 { selectedButton = nil } }
        ), arrowEdge: .trailing) {
            MappingMenu(button: button, eventManager: eventManager)
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
                if mouseType == "G Pro Wireless" || mouseType.contains("ATK") {
                    GProWirelessModel(w: w, h: h, activeCID: $activeCID, selectedButton: $selectedButton, eventManager: eventManager)
                } else if mouseType == "M720 Triathlon" {
                    M720Model(w: w, h: h, activeCID: $activeCID, selectedButton: $selectedButton, eventManager: eventManager)
                } else {
                    GProWirelessModel(w: w, h: h, activeCID: $activeCID, selectedButton: $selectedButton, eventManager: eventManager)
                }
            }
        }
        .frame(width: 200, height: 300)
    }
}

// MARK: - G Pro Wireless (Symmetric, Ambidextrous)
struct GProWirelessModel: View {
    let w: CGFloat
    let h: CGFloat
    @Binding var activeCID: UInt16?
    @Binding var selectedButton: MouseButton?
    @ObservedObject var eventManager: EventTapManager
    
    var body: some View {
        ZStack {
            // Main Chassis
            Path { path in
                path.move(to: CGPoint(x: w*0.3, y: h*0.1))
                path.addCurve(to: CGPoint(x: w*0.5, y: h*0.05), control1: CGPoint(x: w*0.35, y: h*0.05), control2: CGPoint(x: w*0.45, y: h*0.05))
                path.addCurve(to: CGPoint(x: w*0.7, y: h*0.1), control1: CGPoint(x: w*0.55, y: h*0.05), control2: CGPoint(x: w*0.65, y: h*0.05))
                path.addCurve(to: CGPoint(x: w*0.85, y: h*0.5), control1: CGPoint(x: w*0.8, y: h*0.2), control2: CGPoint(x: w*0.88, y: h*0.3))
                path.addCurve(to: CGPoint(x: w*0.75, y: h*0.9), control1: CGPoint(x: w*0.82, y: h*0.7), control2: CGPoint(x: w*0.8, y: h*0.85))
                path.addCurve(to: CGPoint(x: w*0.25, y: h*0.9), control1: CGPoint(x: w*0.6, y: h*0.98), control2: CGPoint(x: w*0.4, y: h*0.98))
                path.addCurve(to: CGPoint(x: w*0.15, y: h*0.5), control1: CGPoint(x: w*0.2, y: h*0.85), control2: CGPoint(x: w*0.12, y: h*0.7))
                path.addCurve(to: CGPoint(x: w*0.3, y: h*0.1), control1: CGPoint(x: w*0.12, y: h*0.3), control2: CGPoint(x: w*0.2, y: h*0.2))
            }
            .stroke(Color.primary.opacity(0.8), lineWidth: 2)
            
            // Separation line for palm
            Path { path in
                path.move(to: CGPoint(x: w*0.2, y: h*0.55))
                path.addCurve(to: CGPoint(x: w*0.8, y: h*0.55), control1: CGPoint(x: w*0.4, y: h*0.5), control2: CGPoint(x: w*0.6, y: h*0.5))
            }
            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
            
            // Left Click
            MouseClickRegion(
                points: [CGPoint(x: w*0.3, y: h*0.1), CGPoint(x: w*0.48, y: h*0.06), CGPoint(x: w*0.48, y: h*0.35), CGPoint(x: w*0.18, y: h*0.35)],
                c1s: [CGPoint(x: w*0.35, y: h*0.05), nil, CGPoint(x: w*0.35, y: h*0.38), CGPoint(x: w*0.15, y: h*0.25)],
                c2s: [CGPoint(x: w*0.45, y: h*0.05), nil, CGPoint(x: w*0.2, y: h*0.38), CGPoint(x: w*0.2, y: h*0.15)]
            )
            
            // Right Click
            MouseClickRegion(
                points: [CGPoint(x: w*0.7, y: h*0.1), CGPoint(x: w*0.52, y: h*0.06), CGPoint(x: w*0.52, y: h*0.35), CGPoint(x: w*0.82, y: h*0.35)],
                c1s: [CGPoint(x: w*0.65, y: h*0.05), nil, CGPoint(x: w*0.65, y: h*0.38), CGPoint(x: w*0.85, y: h*0.25)],
                c2s: [CGPoint(x: w*0.55, y: h*0.05), nil, CGPoint(x: w*0.8, y: h*0.38), CGPoint(x: w*0.8, y: h*0.15)]
            )
            
            // Middle Click / Scroll Wheel
            Capsule()
                .fill(Color.clear)
                .frame(width: w*0.08, height: h*0.15)
                .position(x: w*0.5, y: h*0.2)
                .contentShape(Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 1.5))

            // Side Buttons
            MouseClickRegion(
                points: [CGPoint(x: w*0.15, y: h*0.4), CGPoint(x: w*0.13, y: h*0.42), CGPoint(x: w*0.11, y: h*0.48), CGPoint(x: w*0.13, y: h*0.5)],
                c1s: [nil, nil, nil, nil], c2s: [nil, nil, nil, nil],
                isClosed: true
            )
            
            MouseClickRegion(
                points: [CGPoint(x: w*0.13, y: h*0.52), CGPoint(x: w*0.11, y: h*0.54), CGPoint(x: w*0.09, y: h*0.62), CGPoint(x: w*0.12, y: h*0.64)],
                c1s: [nil, nil, nil, nil], c2s: [nil, nil, nil, nil],
                isClosed: true
            )
            
            // Interactive Badges
            ButtonBadge(label: "L", button: .left, position: CGPoint(x: w*0.35, y: h*0.2), selectedButton: $selectedButton, eventManager: eventManager)
            ButtonBadge(label: "R", button: .right, position: CGPoint(x: w*0.65, y: h*0.2), selectedButton: $selectedButton, eventManager: eventManager)
            ButtonBadge(label: "M", button: .middle, position: CGPoint(x: w*0.5, y: h*0.2), selectedButton: $selectedButton, eventManager: eventManager)
            ButtonBadge(label: "S2", button: .side2, position: CGPoint(x: w*0.05, y: h*0.42), selectedButton: $selectedButton, eventManager: eventManager)
            ButtonBadge(label: "S1", button: .side1, position: CGPoint(x: w*0.03, y: h*0.58), selectedButton: $selectedButton, eventManager: eventManager)
        }
    }
}
// Append to MouseVisualization.swift

// MARK: - M720 Triathlon (Ergonomic Right-Handed)
struct M720Model: View {
    let w: CGFloat
    let h: CGFloat
    @Binding var activeCID: UInt16?
    @Binding var selectedButton: MouseButton?
    @ObservedObject var eventManager: EventTapManager
    
    var body: some View {
        ZStack {
            // Main Chassis (Asymmetrical, bulkier left side for thumb rest)
            Path { path in
                // Start top middle
                path.move(to: CGPoint(x: w*0.4, y: h*0.05))
                path.addCurve(to: CGPoint(x: w*0.75, y: h*0.1), control1: CGPoint(x: w*0.5, y: h*0.02), control2: CGPoint(x: w*0.65, y: h*0.05))
                path.addCurve(to: CGPoint(x: w*0.9, y: h*0.5), control1: CGPoint(x: w*0.85, y: h*0.2), control2: CGPoint(x: w*0.95, y: h*0.35))
                path.addCurve(to: CGPoint(x: w*0.75, y: h*0.95), control1: CGPoint(x: w*0.85, y: h*0.75), control2: CGPoint(x: w*0.8, y: h*0.9))
                path.addCurve(to: CGPoint(x: w*0.15, y: h*0.85), control1: CGPoint(x: w*0.6, y: h*1.0), control2: CGPoint(x: w*0.3, y: h*0.95))
                // Thumb rest wing out
                path.addCurve(to: CGPoint(x: w*0.05, y: h*0.55), control1: CGPoint(x: w*0.05, y: h*0.75), control2: CGPoint(x: w*0.02, y: h*0.65))
                // Curve back in to top
                path.addCurve(to: CGPoint(x: w*0.25, y: h*0.2), control1: CGPoint(x: w*0.1, y: h*0.4), control2: CGPoint(x: w*0.15, y: h*0.3))
                path.addCurve(to: CGPoint(x: w*0.4, y: h*0.05), control1: CGPoint(x: w*0.3, y: h*0.1), control2: CGPoint(x: w*0.35, y: h*0.08))
            }
            .stroke(Color.primary.opacity(0.8), lineWidth: 2)

            // Left Click (Shaped for asymmetrical top)
            MouseClickRegion(
                points: [CGPoint(x: w*0.4, y: h*0.05), CGPoint(x: w*0.5, y: h*0.04), CGPoint(x: w*0.45, y: h*0.35), CGPoint(x: w*0.25, y: h*0.2)],
                c1s: [CGPoint(x: w*0.45, y: h*0.02), nil, CGPoint(x: w*0.3, y: h*0.3), CGPoint(x: w*0.3, y: h*0.1)],
                c2s: [CGPoint(x: w*0.48, y: h*0.03), nil, CGPoint(x: w*0.25, y: h*0.25), CGPoint(x: w*0.35, y: h*0.08)]
            )
            
            // Right Click
            MouseClickRegion(
                points: [CGPoint(x: w*0.75, y: h*0.1), CGPoint(x: w*0.55, y: h*0.05), CGPoint(x: w*0.5, y: h*0.35), CGPoint(x: w*0.88, y: h*0.4)],
                c1s: [CGPoint(x: w*0.65, y: h*0.05), nil, CGPoint(x: w*0.65, y: h*0.4), CGPoint(x: w*0.85, y: h*0.2)],
                c2s: [CGPoint(x: w*0.6, y: h*0.05), nil, CGPoint(x: w*0.8, y: h*0.4), CGPoint(x: w*0.8, y: h*0.15)]
            )
            
            // Middle Click / Scroll Wheel
            Capsule()
                .fill(Color.clear)
                .frame(width: w*0.08, height: h*0.15)
                .position(x: w*0.48, y: h*0.2)
                .contentShape(Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 1.5))

            // Side Buttons (M720 has 3 on the side)
            // Forward
            MouseClickRegion(
                points: [CGPoint(x: w*0.15, y: h*0.35), CGPoint(x: w*0.13, y: h*0.37), CGPoint(x: w*0.1, y: h*0.45), CGPoint(x: w*0.12, y: h*0.47)],
                c1s: [nil, nil, nil, nil], c2s: [nil, nil, nil, nil],
                isClosed: true
            )
            
            // Back
            MouseClickRegion(
                points: [CGPoint(x: w*0.1, y: h*0.48), CGPoint(x: w*0.08, y: h*0.5), CGPoint(x: w*0.08, y: h*0.58), CGPoint(x: w*0.1, y: h*0.6)],
                c1s: [nil, nil, nil, nil], c2s: [nil, nil, nil, nil],
                isClosed: true
            )
            
            // Gesture Button (Bottom edge of thumb rest)
            Path { path in
                path.addEllipse(in: CGRect(x: w*0.08, y: h*0.75, width: w*0.15, height: h*0.06))
            }
            .fill(Color.clear)
            .contentShape(Ellipse())
            .overlay(
                Path { path in
                    path.addEllipse(in: CGRect(x: w*0.08, y: h*0.75, width: w*0.15, height: h*0.06))
                }
                .stroke(Color.primary.opacity(0.15), lineWidth: 1.5)
            )
            
            // Thumb Rest Ridge lines
            Path { path in
                path.move(to: CGPoint(x: w*0.22, y: h*0.65))
                path.addCurve(to: CGPoint(x: w*0.3, y: h*0.8), control1: CGPoint(x: w*0.25, y: h*0.7), control2: CGPoint(x: w*0.28, y: h*0.75))
            }
            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
            
            // Interactive Badges
            ButtonBadge(label: "L", button: .left, position: CGPoint(x: w*0.35, y: h*0.18), selectedButton: $selectedButton, eventManager: eventManager)
            ButtonBadge(label: "R", button: .right, position: CGPoint(x: w*0.65, y: h*0.2), selectedButton: $selectedButton, eventManager: eventManager)
            ButtonBadge(label: "M", button: .middle, position: CGPoint(x: w*0.48, y: h*0.2), selectedButton: $selectedButton, eventManager: eventManager)
            ButtonBadge(label: "S2", button: .side2, position: CGPoint(x: w*0.05, y: h*0.38), selectedButton: $selectedButton, eventManager: eventManager)
            ButtonBadge(label: "S1", button: .side1, position: CGPoint(x: w*0.02, y: h*0.52), selectedButton: $selectedButton, eventManager: eventManager)
            ButtonBadge(label: "T", button: .gesture, position: CGPoint(x: w*0.15, y: h*0.78), selectedButton: $selectedButton, eventManager: eventManager)
        }
    }
}
