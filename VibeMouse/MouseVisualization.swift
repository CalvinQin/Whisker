import SwiftUI

struct MouseVisualization: View {
    let mouseType: String
    @Binding var activeCID: UInt16?
    
    var body: some View {
        ZStack {
            // Main Body
            Capsule()
                .fill(LinearGradient(colors: [Color.primary.opacity(0.1), Color.primary.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                .frame(width: 140, height: 220)
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            
            // Buttons
            HStack(spacing: 2) {
                ButtonRegion(id: 0x0001, label: "L", activeID: activeCID)
                    .frame(width: 68, height: 100)
                ButtonRegion(id: 0x0002, label: "R", activeID: activeCID)
                    .frame(width: 68, height: 100)
            }
            .offset(y: -60)
            
            // Wheel
            RoundedRectangle(cornerRadius: 4)
                .fill(activeCID == 0x0003 ? Color.blue : Color.gray.opacity(0.5))
                .frame(width: 12, height: 40)
                .offset(y: -65)
            
            // Side Buttons
            VStack(spacing: 4) {
                ButtonRegion(id: 0x0004, label: "", activeID: activeCID)
                    .frame(width: 4, height: 30)
                ButtonRegion(id: 0x0005, label: "", activeID: activeCID)
                    .frame(width: 4, height: 30)
            }
            .offset(x: -72, y: -10)
            
            if mouseType == "M720 Triathlon" {
                // Gesture button for M720
                RoundedRectangle(cornerRadius: 2)
                    .fill(activeCID == 0x00C3 ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 2, height: 40)
                    .offset(x: -72, y: 40)
            }
        }
    }
}

struct ButtonRegion: View {
    let id: UInt16
    let label: String
    let activeID: UInt16?
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(id == activeID ? Color.blue.opacity(0.3) : Color.white.opacity(0.05))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
