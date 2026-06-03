import AppKit
import ApplicationServices

/// Grabs the user's current text selection from whatever app is frontmost,
/// and pastes replacement text back in its place — using simulated ⌘C / ⌘V.
/// Requires macOS Accessibility permission (to post keyboard events).
///
/// The blocking calls here (sleeps / polling) must run off the main thread.
enum TextReplacementService {

    static func isTrusted() -> Bool { AXIsProcessTrusted() }

    /// Returns whether the app is trusted; optionally shows the system prompt
    /// that deep-links to Accessibility settings.
    @discardableResult
    static func ensureTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func postCommandKey(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }

    /// Simulates ⌘C and returns the copied selection (or nil if nothing copied).
    static func copySelection() -> String? {
        let pb = NSPasteboard.general
        let before = pb.changeCount
        postCommandKey(8) // 'C'
        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            if pb.changeCount != before { break }
            usleep(15_000)
        }
        guard pb.changeCount != before else { return nil }
        return pb.string(forType: .string)
    }

    /// Puts `text` on the clipboard and simulates ⌘V to paste it.
    static func paste(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        usleep(40_000)
        postCommandKey(9) // 'V'
    }

    static var clipboardString: String? {
        NSPasteboard.general.string(forType: .string)
    }

    static func restoreClipboard(_ value: String?) {
        guard let value else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
    }
}
