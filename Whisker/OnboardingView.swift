import SwiftUI
import AppKit

struct OnboardingView: View {
    @ObservedObject var eventManager: EventTapManager
    
    var body: some View {
        VStack(spacing: 20) {
            // Logo
            Image(systemName: "cursorarrow.click.2")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.bounce.up.byLayer, options: .repeating)
            
            Text("welcomeTitle")
                .font(.title2.bold())
                .foregroundStyle(.white)
            
            Text("welcomeSubtitle")
                .multilineTextAlignment(.center)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            
            // Steps
            VStack(alignment: .leading, spacing: 10) {
                stepRow("1.circle.fill", .purple, "onboardingStep1")
                stepRow("2.circle.fill", .purple, "onboardingStep2")
                stepRow("3.circle.fill", .purple, "onboardingStep3")
                stepRow("4.circle.fill", .cyan, "onboardingStepInput")
                
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                        .padding(.top, 2)
                    Text("onboardingStep4")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .glassCard()
            
            // Permission buttons
            HStack(spacing: 10) {
                Button(action: { openAccessibilitySettings() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.raised.fill")
                        Text("openSettingsBtn")
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                
                Button(action: { openInputMonitoringSettings() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "keyboard.badge.eye")
                        Text("inputMonitoringBtn")
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            
            Button("checkPermissionBtn") {
                eventManager.checkAccessibilityPermission()
                if eventManager.hasAccessibilityPermission {
                    eventManager.start()
                }
            }
            .font(.caption)
            .foregroundColor(.cyan)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.07, blue: 0.16),
                    Color(red: 0.12, green: 0.10, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }
    
    private func stepRow(_ icon: String, _ color: Color, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(color).font(.callout)
            Text(text).font(.callout).foregroundStyle(.white.opacity(0.85))
        }
    }
    
    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            eventManager.checkAccessibilityPermission()
            if eventManager.hasAccessibilityPermission { eventManager.start() }
        }
    }
    
    private func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
