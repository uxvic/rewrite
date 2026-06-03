import AppKit
import AVFoundation
import Speech
import ApplicationServices

/// Thin helpers around the permissions Rewrite can use, plus deep-links to the
/// right System Settings panes.
enum Permissions {
    static func accessibilityGranted() -> Bool { AXIsProcessTrusted() }
    static func microphoneGranted() -> Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    static func speechGranted() -> Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }

    static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
    static func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }
    static func requestSpeech() {
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    static func openAccessibilitySettings() { open("Privacy_Accessibility") }
    static func openMicrophoneSettings() { open("Privacy_Microphone") }
    static func openSpeechSettings() { open("Privacy_SpeechRecognition") }

    private static func open(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
