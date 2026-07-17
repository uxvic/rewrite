import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var welcomeWindow: NSWindow?
    /// The standalone ChatGPT-style window (opened on demand). Kept alive across
    /// close so its conversation state persists; only nilled on quit.
    private var mainWindow: NSWindow?
    private var clickMonitor: Any?
    private let hotKey = HotKeyManager()

    /// The SwiftUI content is hosted ONCE and reused, so moving it between the
    /// docked popover and the torn-off floating panel preserves all in-progress
    /// state (conversation, draft, active dictation).
    private var contentVC: FirstMouseHostingController<PopoverView>!
    /// The floating, persistent window the content tears off into (on drag or
    /// when dictation starts). `nil` while docked.
    private var detachedPanel: FloatingPanel?
    /// Timer that polls the cursor to follow it during a tear-off drag. Polling
    /// (vs. an event monitor) is reliable across the popover→panel window swap,
    /// where the in-flight drag's events route to the now-closed popover window.
    private var dragFollowTimer: Timer?
    /// Cursor offset within the panel at the moment of tear-off, so the window
    /// tracks the pointer at the same relative point while dragging.
    private var dragGrabOffset: NSPoint = .zero

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
        // We drive dismissal ourselves (global click monitor + resign-active) so
        // clicking outside reliably closes it on this menu-bar agent app, where
        // .transient is unreliable after we activate + makeKey the popover window.
        popover.behavior = .applicationDefined
        popover.delegate = self
        // First-mouse hosting so a single click registers even when the agent
        // app's popover window isn't the key window (fixes "click twice to act").
        contentVC = FirstMouseHostingController(rootView: PopoverView())
        popover.contentViewController = contentVC

        registerHotKeys()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(registerHotKeys), name: .hotKeysChanged, object: nil)
        nc.addObserver(self, selector: #selector(appResignedActive),
                       name: NSApplication.didResignActiveNotification, object: nil)
        // Tear-off + voice-persistence signals from the SwiftUI content.
        nc.addObserver(self, selector: #selector(voiceActivated), name: .rewriteVoiceActivated, object: nil)
        nc.addObserver(self, selector: #selector(windowDragChanged), name: .rewriteWindowDragChanged, object: nil)
        nc.addObserver(self, selector: #selector(windowDragEnded), name: .rewriteWindowDragEnded, object: nil)
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

    /// Opens (or focuses) the full app window. While it's open the app becomes a
    /// regular Dock app (icon + Cmd-Tab); it returns to a menu-bar agent on close.
    @objc func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
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

    /// When the main window closes, drop back to a menu-bar agent (no Dock icon).
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === mainWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    @objc func togglePopover(_ sender: Any?) {
        // The menu-bar icon is a toggle: if a torn-off floating window is open,
        // clicking the icon closes it (redocks) — regardless of whether it's the
        // focused window. Previously this only closed when the panel was key, so
        // after dragging it elsewhere and clicking away, the icon just re-focused
        // it and the only way to close was the ✕.
        if detachedPanel != nil {
            redock()
            return
        }
        if popover.isShown { closePopover() } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        // A global monitor fires for clicks that land in another app or the desktop
        // (never for clicks inside our own popover), so this closes on "click outside".
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor); clickMonitor = nil }
        if popover.isShown { popover.performClose(nil) }
    }

    /// Cleans up the monitor however the popover was closed (toggle, Esc, etc.).
    @objc func popoverDidClose(_ notification: Notification) {
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor); clickMonitor = nil }
    }

    /// Only closes the DOCKED popover. A torn-off panel (drag / dictation) is
    /// persistent, so it intentionally survives app deactivation.
    @objc private func appResignedActive() { closePopover() }

    // MARK: - Tear-off into a floating panel

    /// Moves the shared content out of the popover into a persistent floating
    /// panel positioned where the popover was. Reusing `contentVC` preserves all
    /// SwiftUI state. `grabUnderCursor` starts a live drag-follow for tear-off.
    private func detachIntoPanel(grabUnderCursor: Bool) {
        guard detachedPanel == nil else { return }
        // Use the CONTENT's on-screen rect (not the popover window frame, which
        // includes the arrow + chrome) so the panel appears exactly where the
        // content was — no visible jump at tear-off.
        let frame: NSRect = {
            guard let view = popover.contentViewController?.view, let win = view.window else {
                return defaultDetachFrame()
            }
            return win.convertToScreen(view.convert(view.bounds, to: nil))
        }()

        // Detach the content and tear down the docked popover + its click monitor.
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor); clickMonitor = nil }
        popover.contentViewController = nil
        if popover.isShown { popover.performClose(nil) }

        let panel = FloatingPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered, defer: false)
        panel.level = .floating
        // Stay visible across Spaces and full-screen apps, and don't auto-hide
        // when our agent app is no longer active — that's the whole point.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentViewController = contentVC
        if let cv = panel.contentView {
            cv.wantsLayer = true
            cv.layer?.cornerRadius = Metric.window
            cv.layer?.masksToBounds = true
        }
        panel.setFrame(frame, display: true)
        detachedPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // After tear-off the composer re-focuses and AppKit selects ALL its text;
        // a stray keystroke would then wipe the draft. Collapse the selection to the
        // end (keep focus, nothing selected) once focus settles. No-ops in voice mode
        // (the torn-off content has no text field, so the cast fails).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak panel] in
            guard let tv = panel?.firstResponder as? NSTextView else { return }
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        }

        if grabUnderCursor {
            let m = NSEvent.mouseLocation
            dragGrabOffset = NSPoint(x: m.x - panel.frame.origin.x, y: m.y - panel.frame.origin.y)
            // Follow the cursor for the rest of THIS drag, independent of whether
            // the SwiftUI gesture survives the window change.
            startDragFollow()
        }
    }

    /// Moves the content back into the popover (hidden) and disposes the panel, so
    /// the next open is docked again — with state intact (same `contentVC`).
    private func redock() {
        stopDragFollow()
        guard let panel = detachedPanel else { return }
        // If dictation is live in the panel, end it cleanly so the mic is released.
        NotificationCenter.default.post(name: .rewriteForceExitVoice, object: nil)
        panel.contentViewController = nil
        panel.orderOut(nil)
        detachedPanel = nil
        popover.contentViewController = contentVC
    }

    private func startDragFollow() {
        stopDragFollow()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Stop once the left button is released — works even if the drag's
            // mouse-up never reaches us after the window swap.
            if NSEvent.pressedMouseButtons & 0x1 == 0 {
                self.stopDragFollow()
            } else {
                self.moveDetachedToCursor()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dragFollowTimer = timer
    }

    private func stopDragFollow() {
        dragFollowTimer?.invalidate()
        dragFollowTimer = nil
    }

    private func moveDetachedToCursor() {
        guard let panel = detachedPanel else { return }
        let m = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: m.x - dragGrabOffset.x, y: m.y - dragGrabOffset.y))
    }

    /// Centered fallback when we can't read the popover's on-screen frame.
    private func defaultDetachFrame() -> NSRect {
        let size = NSSize(width: 380, height: 668)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(x: screen.midX - size.width / 2,
                      y: screen.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    // MARK: - Content signals

    @objc private func voiceActivated() {
        // Dictation must persist regardless of clicks/app switches — detach if
        // we're still docked. (No drag-follow; it just floats in place.)
        if detachedPanel == nil { detachIntoPanel(grabUnderCursor: false) }
    }

    @objc private func windowDragChanged() {
        if detachedPanel == nil {
            detachIntoPanel(grabUnderCursor: true)   // tear off + begin follow
        } else {
            moveDetachedToCursor()
        }
    }

    @objc private func windowDragEnded() { stopDragFollow() }

    /// The header ✕ / Esc: dismiss whatever surface is showing.
    @objc private func closeWindow() {
        if detachedPanel != nil { redock() } else { closePopover() }
    }

    /// Menu-bar "Settings…": make sure a window is showing, then switch it to the
    /// Settings panel.
    @objc private func openSettings() {
        if let panel = detachedPanel {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else if !popover.isShown {
            showPopover()
        }
        NotificationCenter.default.post(name: .rewriteShowSettings, object: nil)
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
                                        input: selection, output: result, mode: .writing)
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
    static let rewriteWindowDragChanged = Notification.Name("RewriteWindowDragChanged")
    static let rewriteWindowDragEnded   = Notification.Name("RewriteWindowDragEnded")
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
