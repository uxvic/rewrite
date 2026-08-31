import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var welcomeWindow: NSWindow?
    /// The standalone ChatGPT-style window (opened on demand). Kept alive across
    /// close so its conversation state persists; only nilled on quit.
    private var mainWindow: NSWindow?
    private var clickMonitor: Any?
    private let hotKey = HotKeyManager()

    /// The SwiftUI content is hosted ONCE and reused, so hiding/showing the glass
    /// panel preserves all in-progress state (conversation, draft, dictation).
    private var contentVC: FirstMouseHostingController<PopoverView>!
    /// The ONE quick surface: a borderless, fully transparent floating panel under
    /// the menu-bar icon. There is no popover chrome and no window background —
    /// only the SwiftUI glass elements render. (This replaced NSPopover when the
    /// popover went background-less; NSPopover always paints its own frame.)
    private var glassPanel: FloatingPanel?
    /// Live dictation must survive clicks into other apps, so while it's on we
    /// skip the auto-close paths (outside click / app deactivation).
    private var voiceActive = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Rewrite")
            button.action = #selector(statusButtonClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // First-mouse hosting so a single click registers even when the agent
        // app's panel isn't the key window (fixes "click twice to act").
        contentVC = FirstMouseHostingController(rootView: PopoverView())

        registerHotKeys()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(registerHotKeys), name: .hotKeysChanged, object: nil)
        nc.addObserver(self, selector: #selector(appResignedActive),
                       name: NSApplication.didResignActiveNotification, object: nil)
        // Voice-persistence signals from the SwiftUI content.
        nc.addObserver(self, selector: #selector(voiceStarted), name: .rewriteVoiceActivated, object: nil)
        nc.addObserver(self, selector: #selector(voiceEnded), name: .rewriteVoiceEnded, object: nil)
        nc.addObserver(self, selector: #selector(closeWindow), name: .rewriteCloseWindow, object: nil)

        _ = AppUpdater.shared   // starts Sparkle + scheduled checks

        if !UserDefaults.standard.bool(forKey: "didOnboard") {
            UserDefaults.standard.set(true, forKey: "didOnboard")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.showWelcome() }
        }

        // Launch like a normal app: open the main window (Dock icon + Cmd-Tab).
        // The menu-bar ✦ stays for the quick popover + the in-place hotkey.
        showMainWindow()
    }

    /// Relaunching from Launchpad/Finder/Spotlight (or clicking the Dock icon)
    /// reopens the window even after we've dropped back to a menu-bar agent.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
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
        menu.addItem(withTitle: "Open in Window", action: #selector(showMainWindow), keyEquivalent: "n").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
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

    // MARK: - Standalone ChatGPT-style window

    /// Opens (or focuses) the full app window. The app stays a menu-bar agent
    /// (LSUIElement / .accessory) the whole time — promoting it to a .regular Dock
    /// app made it own a Space, which yanked the menu-bar popover to the desktop
    /// instead of floating it over your current app. The window still opens and
    /// focuses fine as an accessory window.
    @objc func showMainWindow() {
        if let w = mainWindow {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Rewrite"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false

        // Host the SwiftUI content and STOP it from driving the window size —
        // NSHostingController otherwise overrides the min/max we set (that's why the
        // width cap wasn't sticking).
        let hosting = NSHostingController(rootView: MainWindowView())
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.delegate = self

        // Like System Settings: capped width (can't be dragged wider, so the content
        // layout stays controlled) but freely resizable taller. Set AFTER the content
        // controller so they stick.
        window.minSize = NSSize(width: 820, height: 480)
        window.maxSize = NSSize(width: 1040, height: CGFloat.greatestFiniteMagnitude)
        window.setContentSize(NSSize(width: 1000, height: 680))
        window.center()
        window.setFrameAutosaveName("RewriteMainWindow")   // remembers size

        // A frame saved before the cap (or restored too wide) — clamp it now.
        if window.frame.width > Self.maxWindowWidth {
            var f = window.frame
            f.size.width = Self.maxWindowWidth
            window.setFrame(f, display: false)
        }

        mainWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Hard cap on the main window's width (System-Settings style: no wider, any taller).
    private static let maxWindowWidth: CGFloat = 1040

    /// Bulletproof width cap: clamp every resize (maxSize alone was being overridden
    /// by the SwiftUI hosting controller). Height is unconstrained here.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === mainWindow else { return frameSize }
        return NSSize(width: min(frameSize.width, Self.maxWindowWidth), height: frameSize.height)
    }


    @objc func togglePopover(_ sender: Any?) {
        if let panel = glassPanel, panel.isVisible { hideGlassPanel() } else { showGlassPanel() }
    }

    /// The size of the invisible panel. Wider/taller than the content column so
    /// element shadows and glows render inside the window instead of clipping at
    /// its edges; content hangs from the top (right under the icon).
    private static let panelSize = NSSize(width: 424, height: 700)

    /// Shows the background-less quick surface: a transparent, borderless panel
    /// anchored under the menu-bar icon. Only the SwiftUI glass elements draw.
    private func showGlassPanel() {
        let panel: FloatingPanel
        if let existing = glassPanel {
            panel = existing
        } else {
            panel = FloatingPanel(
                contentRect: NSRect(origin: .zero, size: Self.panelSize),
                styleMask: [.borderless],
                backing: .buffered, defer: false)
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            // No window shadow: the window is invisible — each glass element
            // draws its own shadow instead.
            panel.hasShadow = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.isReleasedWhenClosed = false
            // The floating glass keeps ONE identity — smoked dark glass with light
            // text, like the reference. Materials/glass follow the WINDOW's
            // appearance (not the pixels behind them), so forcing dark makes the
            // elements read grey over a white page and near-black over a dark one —
            // never washed out light-on-light.
            panel.appearance = NSAppearance(named: .darkAqua)
            panel.contentViewController = contentVC
            glassPanel = panel
        }

        // Re-anchor under the icon only when (re)opening, not when it's already up.
        if !panel.isVisible { panel.setFrame(anchoredPanelFrame(), display: true) }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // Re-run clipboard auto-fill + What's New on every show (orderOut doesn't
        // re-fire SwiftUI's .onAppear).
        DispatchQueue.main.async { NotificationCenter.default.post(name: .rewritePanelWillShow, object: nil) }

        // A global monitor fires for clicks that land in another app or the desktop
        // (never inside our own panel), so this closes on "click outside" — except
        // while dictation is live, which must survive clicking around.
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self, !self.voiceActive else { return }
                self.hideGlassPanel()
            }
        }
    }

    private func hideGlassPanel() {
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor); clickMonitor = nil }
        // If dictation is live, end it cleanly so the mic is released.
        if voiceActive { NotificationCenter.default.post(name: .rewriteForceExitVoice, object: nil) }
        voiceActive = false
        glassPanel?.orderOut(nil)
    }

    /// The panel frame tucked under the menu-bar icon (centered on it, clamped to
    /// the screen), like the popover used to sit.
    private func anchoredPanelFrame() -> NSRect {
        let size = Self.panelSize
        guard let button = statusItem.button, let bwin = button.window else {
            let vis = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            return NSRect(x: vis.midX - size.width / 2, y: vis.maxY - size.height - 8,
                          width: size.width, height: size.height)
        }
        let bframe = bwin.convertToScreen(button.convert(button.bounds, to: nil))
        var x = bframe.midX - size.width / 2
        if let vis = (bwin.screen ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, vis.minX + 8), vis.maxX - size.width - 8)
        }
        let y = bframe.minY - size.height - 6
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Closes the quick surface on app deactivation — except while dictation is
    /// live, which is exactly when the user is off in another app talking.
    @objc private func appResignedActive() {
        if !voiceActive { hideGlassPanel() }
    }

    // MARK: - Content signals

    @objc private func voiceStarted() { voiceActive = true }
    @objc private func voiceEnded() { voiceActive = false }

    /// The ✕ / Esc from the content: dismiss the quick surface.
    @objc private func closeWindow() { hideGlassPanel() }

    /// Menu-bar "Settings…": make sure the quick surface is showing, then switch
    /// it to the Settings panel.
    @objc private func openSettings() {
        showGlassPanel()
        // async so the content's .onReceive is subscribed before the post (on a
        // first open the panel's SwiftUI tree may not be committed yet).
        DispatchQueue.main.async { NotificationCenter.default.post(name: .rewriteShowSettings, object: nil) }
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
                                        input: selection, output: result, mode: .rewrite)
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

/// Notifications the SwiftUI content sends to the host (AppDelegate) to drive
/// tear-off and dictation persistence.
extension Notification.Name {
    static let rewriteVoiceActivated   = Notification.Name("RewriteVoiceActivated")
    static let rewriteVoiceEnded       = Notification.Name("RewriteVoiceEnded")
    static let rewritePanelWillShow    = Notification.Name("RewritePanelWillShow")
    static let rewriteCloseWindow       = Notification.Name("RewriteCloseWindow")
    static let rewriteShowSettings      = Notification.Name("RewriteShowSettings")
    static let rewriteForceExitVoice    = Notification.Name("RewriteForceExitVoice")
}

/// Borderless panel that can still become key for the composer + dictation, used
/// for the torn-off / voice window.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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
