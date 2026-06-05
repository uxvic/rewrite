import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var welcomeWindow: NSWindow?
    private let hotKey = HotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Rewrite")
            button.action = #selector(statusButtonClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 668)
        popover.behavior = .transient
        // First-mouse hosting so a single click registers even when the agent
        // app's popover window isn't the key window (fixes "click twice to act").
        popover.contentViewController = FirstMouseHostingController(rootView: PopoverView())

        registerHotKeys()
        NotificationCenter.default.addObserver(self, selector: #selector(registerHotKeys),
                                               name: .hotKeysChanged, object: nil)

        _ = AppUpdater.shared   // starts Sparkle + scheduled checks

        if !UserDefaults.standard.bool(forKey: "didOnboard") {
            UserDefaults.standard.set(true, forKey: "didOnboard")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.showWelcome() }
        }
    }

    @objc private func showWelcome() {
        if let w = welcomeWindow { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = NSHostingController(rootView: WelcomeView(onClose: { [weak self] in
            self?.welcomeWindow?.close()
        }))
        welcomeWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func registerHotKeys() {
        let s = AppSettings.shared
        let pop = HotKeyCombo.byID(s.popoverHotKeyID)
        let inPlace = HotKeyCombo.byID(s.inPlaceHotKeyID)
        hotKey.setBindings([
            .init(id: 1, keyCode: pop.keyCode, modifiers: pop.modifiers) { [weak self] in
                self?.togglePopover(nil)
            },
            .init(id: 2, keyCode: inPlace.keyCode, modifiers: inPlace.modifiers) { [weak self] in
                self?.rewriteSelectionInPlace()
            }
        ])
    }

    @objc private func statusButtonClicked() {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isRightClick {
            showStatusMenu()
        } else {
            togglePopover(nil)
        }
    }

    private func showStatusMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Rewrite", action: #selector(togglePopover(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Welcome / Help", action: #selector(showWelcome), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(withTitle: "About Rewrite", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Rewrite", action: #selector(quit), keyEquivalent: "q").target = self
        let origin = NSPoint(x: 0, y: button.bounds.height + 5)
        menu.popUp(positioning: nil, at: origin, in: button)
    }

    @objc private func checkForUpdates() {
        AppUpdater.shared.checkForUpdates()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let credits = NSAttributedString(
            string: "A private writing assistant in your menu bar.",
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Rewrite",
            .applicationVersion: version,
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© 2026 Rewrite"
        ])
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Rewrite selection in place (anywhere)

    private func rewriteSelectionInPlace() {
        guard TextReplacementService.ensureTrusted(prompt: true) else {
            // The system prompt (deep-link to Accessibility settings) was shown.
            return
        }
        let settings = AppSettings.shared
        let action = settings.defaultInPlaceAction
        let provider = settings.makeProvider()

        Task.detached {
            let originalClipboard = TextReplacementService.clipboardString
            guard let selection = TextReplacementService.copySelection(),
                  !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await MainActor.run {
                    self.showError("Couldn't read any selected text. Select some text first, then press the hotkey.")
                }
                return
            }
            do {
                let raw = try await provider.stream(text: RewriteAction.wrap(selection),
                                                    systemPrompt: action.systemPrompt,
                                                    onDelta: { _ in })
                let result = RewriteAction.clean(raw)
                TextReplacementService.paste(result)
                try? await Task.sleep(nanoseconds: 400_000_000)
                TextReplacementService.restoreClipboard(originalClipboard)
                await MainActor.run {
                    settings.addHistory(actionLabel: "\(action.label) (in place)",
                                        input: selection, output: result)
                }
            } catch {
                TextReplacementService.restoreClipboard(originalClipboard)
                await MainActor.run { self.showError("Rewrite failed: \(error.localizedDescription)") }
            }
        }
    }

    @MainActor
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Rewrite"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

/// NSHostingView that accepts the first mouse click. In a menu-bar agent app the
/// popover window often isn't key, so without this the first click on any control
/// is consumed just to activate the window ("click twice to act").
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @MainActor required init(rootView: Content) { super.init(rootView: rootView) }
    @MainActor required init?(coder: NSCoder) { super.init(coder: coder) }
}

final class FirstMouseHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() { view = FirstMouseHostingView(rootView: rootView) }
}
