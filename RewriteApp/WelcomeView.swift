import SwiftUI

/// First-run welcome shown in a standalone window — explains where the app
/// lives (menu bar agents open to nothing otherwise), the hotkeys, the default
/// engine, and offers permission primers.
struct WelcomeView: View {
    var onClose: () -> Void
    @State private var tick = false   // toggled to re-read permission status

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "wand.and.stars").font(.system(size: 24)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("REWRITE").font(.display(22)).tracking(2).foregroundStyle(Theme.textPrimary)
                    Text("A private writing assistant in your menu bar.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            HairlineDivider()

            infoRow("menubar.arrow.up.rectangle", "It lives in your menu bar",
                    "Click the ✨ icon at the top-right of your screen to open it. Right-click it for Quit & About.")
            infoRow("keyboard", "Hotkeys",
                    "⌥Space opens Rewrite anywhere. ⌥⇧Space rewrites the text you've selected in any app.")
            infoRow("bolt.fill", engineTitle, engineSubtitle)

            HairlineDivider()
            SectionLabel(text: "PERMISSIONS · OPTIONAL")
            permissionRow("Accessibility",
                          "Lets ⌥⇧Space rewrite selected text anywhere.",
                          granted: Permissions.accessibilityGranted()) {
                Permissions.promptAccessibility(); Permissions.openAccessibilitySettings()
            }
            permissionRow("Microphone",
                          "Lets you dictate instead of typing.",
                          granted: Permissions.microphoneGranted()) {
                Permissions.requestMicrophone()
            }

            Spacer(minLength: 0)
            HStack {
                Button { tick.toggle() } label: { Text("REFRESH STATUS") }
                    .buttonStyle(InstrumentButtonStyle()).controlSize(.small)
                Spacer()
                Button { onClose() } label: { Text("GET STARTED") }
                    .buttonStyle(InstrumentButtonStyle(prominent: true))
            }
        }
        .padding(24)
        .frame(width: 460, height: 560)
        .background(Theme.bg)
        .id(tick)
    }

    private var engineTitle: String {
        AppleOnDeviceProvider.isAvailable ? "Ready to use — nothing to set up" : "Pick a free engine in Settings"
    }
    private var engineSubtitle: String {
        AppleOnDeviceProvider.isAvailable
        ? "Powered by Apple's on-device AI: free, private, offline. Just open it and start rewriting."
        : "Your Mac can't use the built-in AI yet — open Settings (gear) to use the free newsletter models, a local model, or your own key."
    }

    private func infoRow(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Theme.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(body).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func permissionRow(_ title: String, _ body: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            LEDDot(color: granted ? Theme.accent : Theme.textSecondary).padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(body).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Text("GRANTED").font(.mono(9)).tracking(1).foregroundStyle(Theme.accent)
            } else {
                Button { action() } label: { Text("ENABLE") }
                    .buttonStyle(InstrumentButtonStyle()).controlSize(.small)
            }
        }
    }
}
