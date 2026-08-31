import SwiftUI
import AppKit
import Combine

/// One message in the rewrite conversation. User turns hold the source text;
/// assistant turns hold a rewrite (streamed in) plus the action that produced it.
struct ChatTurn: Identifiable, Equatable, Codable {
    enum Role: String, Codable { case user, assistant, setup, whatsNew }
    var id = UUID()
    var role: Role
    var text: String
    var actionLabel: String = ""
    var systemPrompt: String = ""
    var isStreaming: Bool = false
    var isError: Bool = false
    var showingDiff: Bool = false
    var sourceText: String = ""
    var fromClipboard: Bool = false
    /// Smart "Request" turns fulfill an instruction rather than rewrite text, so
    /// they must NOT be re-wrapped on retry and a source/result diff is meaningless.
    var fulfillsRequest: Bool = false
    /// A Smart (decide-and-act) turn. Drives tag-stripping while streaming and lets
    /// Retry re-run the Smart pass. `rawText` accumulates the raw tagged stream so
    /// the [REWRITE]/[REQUEST] tag can be parsed incrementally; `text` stays clean.
    var isSmart: Bool = false
    var rawText: String = ""
}

/// What the composer's text means when sent: new source text, or a one-off
/// custom instruction to run on the latest source.
enum ComposerMode { case text, instruction }

/// An action picked from the action bar, applied to text when it's sent.
struct SelectedAction: Equatable { let id: String; let systemPrompt: String; let label: String }

/// A run to re-attempt after the user finishes provider setup in the chat.
struct PendingRun: Equatable { let systemPrompt: String; let label: String; let source: String; var smart: Bool = false }

struct PopoverView: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var speech = SpeechManager()

    @State private var threadByMode: [RewriteMode: [ChatTurn]] = [:]
    // Shared with the app window: the popover mirrors each mode's thread into one
    // of these saved conversations (created lazily on the first real turn), so a
    // chat started here shows up in the window and vice-versa. `currentConvoID`
    // maps a mode to the conversation its thread is currently backed by.
    @ObservedObject private var store = ConversationStore.shared
    @State private var currentConvoID: [RewriteMode: UUID] = [:]
    // The unified flow keeps one draft and one active conversation key.
    @State private var draft: String = ""
    @State private var composerMode: ComposerMode = .text
    @State private var selectedAction: SelectedAction?
    @State private var pendingRetry: PendingRun?
    @State private var showSelectPrompt = false
    @State private var isLoading = false
    @State private var currentTask: Task<Void, Never>?
    @State private var copiedTurnID: UUID?
    // Reflects the composer's actual first-responder state (reported by the
    // native input view); drives only the focus-highlight border now.
    @State private var composerFocused: Bool = false
    @State private var voiceMode = false
    @State private var fromClipboard = false
    @State private var lastClipboardCount = -1

    private enum Panel { case main, settings, history }
    @State private var panel: Panel = .main

    /// The unified Rewrite flow shown by the saved-chat panel.
    @State private var historyMode: RewriteMode = .rewrite

    /// The dictionary preserves the existing storage shape while the product has
    /// one canonical Rewrite key.
    private var thread: [ChatTurn] {
        get { threadByMode[settings.mode] ?? [] }
        nonmutating set { threadByMode[settings.mode] = newValue }
    }

    var body: some View {
        Group {
            if voiceMode {
                VoiceOverlayView(speech: speech, onDone: finishVoice, onCancel: cancelVoice)
            } else {
                // Background-less design: the window is fully transparent — only
                // the floating glass elements draw. Settings/Chats are the
                // exception: dense surfaces that render on one big glass card.
                Group {
                    switch panel {
                    case .main:     mainSurface
                    case .settings: panelCard(title: "Settings") { SettingsView() }
                    case .history:  panelCard(title: "Chats") { historyPanel }
                    }
                }
                // Esc dismisses the floating surface.
                .onExitCommand { NotificationCenter.default.post(name: .rewriteCloseWindow, object: nil) }
            }
        }
        .frame(width: 424, height: 700)
        .onAppear { autoFillFromClipboard(); injectWhatsNewIfNeeded() }
        // The panel is hidden with orderOut (the hosting view stays attached), so
        // SwiftUI never re-fires .onAppear on reopen. The host posts this on every
        // show so clipboard auto-fill + What's New re-run each time, as they did
        // when the NSPopover detached/reattached its content.
        .onReceive(NotificationCenter.default.publisher(for: .rewritePanelWillShow)) { _ in
            autoFillFromClipboard(); injectWhatsNewIfNeeded()
        }
        .onChange(of: settings.mode) { _, _ in selectedAction = nil; composerMode = .text; showSelectPrompt = false; injectWhatsNewIfNeeded() }
        // Host is dismissing a torn-off window while dictation is live — end it
        // cleanly so the mic is released.
        .onReceive(NotificationCenter.default.publisher(for: .rewriteForceExitVoice)) { _ in
            if voiceMode { cancelVoice() }
        }
        // Opened from the menu-bar "Settings…" item. If dictation is live, end it
        // cleanly (releases the mic) — otherwise leaving voice this way leaks it.
        .onReceive(NotificationCenter.default.publisher(for: .rewriteShowSettings)) { _ in
            if voiceMode { cancelVoice() }
            panel = .settings
        }
    }

    // MARK: - Main surface (background-less)

    /// The chat as floating glass over the desktop: thread on top, the composer
    /// card, then the Rewrite tab — nothing containing them. There is no
    /// header; Chats/Settings live in the composer's tool row (and the menu-bar
    /// right-click menu), ✕ is replaced by Esc / click-outside / icon toggle.
    private var mainSurface: some View {
        VStack(spacing: 12) {
            modeSegmented($settings.mode, width: 220)   // Rewrite — at the TOP of the chat
            threadView
            composer
        }
        // Hang from the TOP so the whole stack sits right under the menu-bar icon
        // (no basin above it). The 22pt gutters give element shadows + the blob
        // room inside the invisible window instead of clipping at its edges.
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .background(contrastBlob)   // separates the glass from any desktop, light or dark
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// A soft blob behind the whole stack so the glass never blends into the
    /// desktop: a dark halo reads it apart on a LIGHT background, a faint light
    /// halo on a DARK one. (Sampling the actual wallpaper would need screen-
    /// recording permission; this dual halo needs none and works either way.)
    private var contrastBlob: some View {
        RoundedRectangle(cornerRadius: 40, style: .continuous)
            .fill(Color.black.opacity(0.30))
            .blur(radius: 22)          // a soft cloud, not a crisp box — no "cropped" frame
            .padding(-10)
            .shadow(color: Color.black.opacity(0.6), radius: 34, y: 10)    // pops on light
            .shadow(color: Color.white.opacity(0.12), radius: 16)          // pops on dark
            .allowsHitTesting(false)
    }

    /// Settings / Chats are dense surfaces that need a readable ground, so they
    /// render on one big glass card with a small header row of their own.
    private func panelCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                IconButton(systemName: "chevron.left", size: 30, help: "Back") { panel = .main }
                Spacer()
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                IconButton(systemName: "xmark", size: 30, help: "Close") {
                    NotificationCenter.default.post(name: .rewriteCloseWindow, object: nil)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            content()
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .liquidGlass(RoundedRectangle(cornerRadius: 30, style: .continuous))
        // Room for the card's shadow inside the invisible window (radius 14, y 6).
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 22)
    }

    /// The unified Rewrite marker remains a small glass control at the top of the
    /// floating surface. Clipboard will become its second destination later.
    private func modeSegmented(_ selection: Binding<RewriteMode>, width: CGFloat = 200) -> some View {
        HStack(spacing: 0) {
            ForEach(RewriteMode.allCases) { m in
                let active = selection.wrappedValue == m
                Text(m.title.capitalized)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(active ? Theme.accentInk : Theme.textSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background {
                        if active { Capsule().fill(Theme.accent) }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { selection.wrappedValue = m } }
            }
        }
        .padding(3)
        .liquidGlass(Capsule())
        .frame(width: width)
    }

    // MARK: - What's new

    private var showWhatsNew: Bool {
        settings.lastSeenWhatsNewVersion != AppUpdater.shared.featureVersion
    }

    /// After a feature update, drop the full What's New card straight into the
    /// conversation (top of the thread) so it's seen in the chat — not behind a
    /// banner. Runs on appear and on mode switch; no-ops once seen or already present.
    private func injectWhatsNewIfNeeded() {
        guard showWhatsNew, !thread.contains(where: { $0.role == .whatsNew }) else { return }
        thread.insert(ChatTurn(role: .whatsNew, text: ""), at: 0)
    }

    private func markWhatsNewSeen() {
        settings.lastSeenWhatsNewVersion = AppUpdater.shared.featureVersion
    }

    /// Dismiss clears the card from every mode's thread and marks the feature
    /// line seen, so it won't re-inject in either tab until the next update.
    private func dismissWhatsNew(_ id: UUID) {
        for m in RewriteMode.allCases { threadByMode[m]?.removeAll { $0.role == .whatsNew } }
        markWhatsNewSeen()
    }

    /// Height cap for the thread; beyond it the thread scrolls and fades at the top.
    private static let threadCap: CGFloat = 430
    @State private var threadHeight: CGFloat = 0

    /// The thread hangs from the top (right under the menu-bar icon) and grows
    /// downward: exactly as tall as its content until the cap, then it scrolls —
    /// and with no window edge to clip against, old bubbles FADE OUT at the top.
    private var threadView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if thread.isEmpty {
                        emptyState
                    } else {
                        ForEach(thread) { turn in turnView(turn) }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 2)
                .background(GeometryReader { g in
                    Color.clear.preference(key: ThreadHeightKey.self, value: g.size.height)
                })
            }
            .onPreferenceChange(ThreadHeightKey.self) { threadHeight = $0 }
            .frame(height: min(threadHeight, Self.threadCap))
            .mask {
                if threadHeight > Self.threadCap {
                    // Fade only the TOP while scrolling; extend the opaque region
                    // past the sides/bottom so bubble shadows aren't clipped there.
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    .padding(.horizontal, -80).padding(.bottom, -80)
                } else {
                    // Short chats: an opaque mask extended well past the bounds so
                    // NOTHING clips — no boxy "cropped" edge around the bubbles.
                    Rectangle().padding(-80)
                }
            }
            .onChange(of: thread) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    /// The opening guidance arrives as an assistant chat bubble (not a big centered
    /// card), so an empty chat already looks like a conversation.
    private var emptyState: some View {
        HStack {
            Text("Paste, type, or dictate text to rework. You can also ask Rewrite to draft something new.")
                .font(.system(size: 13.5)).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .liquidGlass(RoundedRectangle(cornerRadius: Metric.bubbleRadius, style: .continuous))
            Spacer(minLength: 36)
        }
    }

    @ViewBuilder
    private func turnView(_ turn: ChatTurn) -> some View {
        switch turn.role {
        case .user:      userBubble(turn)
        case .assistant: assistantTurn(turn)
        case .setup:     SetupCardView(onReady: retryPending) { dismissSetup(turn.id) }
        case .whatsNew:  WhatsNewCardView { dismissWhatsNew(turn.id) }
        }
    }

    private func userBubble(_ turn: ChatTurn) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            if turn.fromClipboard {
                Text("From clipboard").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            Text(turn.text)
                .font(.system(size: 13.5)).foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 14).padding(.vertical, 10)
                // A step lighter than the reply glass, like the reference's grey pill.
                .background(RoundedRectangle(cornerRadius: Metric.bubbleRadius, style: .continuous)
                    .fill(Theme.fillTranslucent.opacity(0.10)))
                .liquidGlass(RoundedRectangle(cornerRadius: Metric.bubbleRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 36)
    }

    private func assistantTurn(_ turn: ChatTurn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(turn.isError ? Theme.ledFail : Theme.accent).frame(width: 6, height: 6)
                Text(turn.actionLabel).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(turn.isError ? Theme.ledFail : Theme.accent)
                    .lineLimit(1)
            }
            if turn.isStreaming && turn.text.isEmpty {
                TypingDots()
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .liquidGlass(RoundedRectangle(cornerRadius: Metric.bubbleRadius, style: .continuous))
            } else {
                bodyText(turn)
                    .font(.system(size: 13.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .liquidGlass(RoundedRectangle(cornerRadius: Metric.bubbleRadius, style: .continuous))
                    .overlay {
                        if turn.isStreaming {
                            RoundedRectangle(cornerRadius: Metric.bubbleRadius, style: .continuous)
                                .stroke(Theme.accent.opacity(0.5), lineWidth: 1)
                        }
                    }
            }
            if !turn.isStreaming && !turn.isError {
                assistantActions(turn)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 24)
    }

    private func bodyText(_ turn: ChatTurn) -> Text {
        if turn.isError { return Text(turn.text).foregroundColor(Theme.ledFail) }
        if turn.showingDiff { return diffText(turn) }
        let base = Text(turn.text).foregroundColor(Theme.textPrimary)
        return turn.isStreaming ? base + Text(" ▏").foregroundColor(Theme.accent) : base
    }

    private func diffText(_ turn: ChatTurn) -> Text {
        TextDiff.words(old: turn.sourceText, new: turn.text).reduce(Text("")) { acc, seg in
            switch seg.kind {
            case .same:    return acc + Text(seg.text).foregroundColor(Theme.textPrimary)
            case .added:   return acc + Text(seg.text).foregroundColor(Theme.accent)
            case .removed: return acc + Text(seg.text).foregroundColor(Theme.ledFail).strikethrough()
            }
        }
    }

    private func assistantActions(_ turn: ChatTurn) -> some View {
        HStack(spacing: 6) {
            miniButton(copiedTurnID == turn.id ? "checkmark" : "doc.on.doc",
                       copiedTurnID == turn.id ? "Copied" : "Copy") {
                setClipboard(turn.text)
                copiedTurnID = turn.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    if copiedTurnID == turn.id { copiedTurnID = nil }
                }
            }
            miniButton("arrow.up", "Use") { draft = turn.text; composerMode = .text }
            retryMenu(turn)
            // A source/result diff only makes sense for rewrites, not fulfilled requests.
            if !turn.fulfillsRequest {
                miniButton(turn.showingDiff ? "text.alignleft" : "plus.forwardslash.minus",
                           turn.showingDiff ? "Result" : "Diff") {
                    mutateTurn(turn.id) { $0.showingDiff.toggle() }
                }
            }
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.5 : 1)
    }

    private func miniButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            miniCapsule(icon, label)
        }
        .buttonStyle(.plain)
    }

    /// The shared capsule look used by the mini action buttons (and the Retry menu).
    private func miniCapsule(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10))
            Text(label).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Theme.fillTranslucent.opacity(0.06)))
        .contentShape(Capsule())
    }

    /// Retry is a menu, not a one-shot: instead of silently re-running the same
    /// thing (or, on Smart, re-guessing intent), it lets the user pick HOW to redo
    /// it — try again as-is, or rewrite the original text in a specific tone/style.
    /// Every option re-runs against the turn's source text (the original input).
    private func retryMenu(_ turn: ChatTurn) -> some View {
        Menu {
            Button {
                run(systemPrompt: turn.systemPrompt, label: turn.actionLabel,
                    variation: true, source: turn.sourceText,
                    wrap: !turn.fulfillsRequest, smart: turn.isSmart)
            } label: { Label("Try again", systemImage: "arrow.clockwise") }
            Divider()
            Section("Rewrite as…") {
                ForEach(RewriteAction.allCases) { action in
                    Button {
                        run(systemPrompt: action.systemPrompt, label: action.label,
                            source: turn.sourceText, wrap: true, smart: false)
                    } label: { Label(action.label, systemImage: action.systemImage) }
                }
            }
        } label: {
            miniCapsule("arrow.clockwise", "Retry")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Action bar (pick an action, then type & send)

    /// Horizontal, scrollable row of actions under the composer. Tap to select;
    /// the selected action is applied to the text when it's sent.
    private var actionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                // Smart governs the plain (no-action) send in BOTH modes: Writing
                // polishes text or fulfills a request; Prompt optimizes a draft prompt
                // or just does it when the input is really content/a request. It's
                // mutually exclusive with the explicit actions — picking one deselects
                // the others. `smartIntent` stays the persistent default; a picked
                // action is a per-send override that hides Smart's highlight.
                selectableChip(icon: "sparkles", label: "Smart",
                               selected: settings.smartIntent && selectedAction == nil && composerMode == .text) {
                    let smartActive = settings.smartIntent && selectedAction == nil && composerMode == .text
                    selectedAction = nil
                    composerMode = .text
                    showSelectPrompt = false
                    settings.smartIntent = !smartActive
                }
                ForEach(Array(settings.mode.actions.enumerated()), id: \.element.id) { idx, action in
                    selectableChip(icon: action.systemImage, label: action.label,
                                   selected: selectedAction?.id == action.id) {
                        selectAction(SelectedAction(id: action.id, systemPrompt: action.systemPrompt, label: action.label))
                    }
                    .keyboardShortcut(shortcutKey(idx), modifiers: .command)
                }
                ForEach(settings.customPresets) { preset in
                    selectableChip(icon: "star", label: preset.label,
                                   selected: selectedAction?.id == preset.id) {
                        selectAction(SelectedAction(id: preset.id,
                                                    systemPrompt: RewriteAction.customSystemPrompt(preset.instruction),
                                                    label: preset.label))
                    }
                }
                selectableChip(icon: "wand.and.rays", label: "Custom…",
                               selected: composerMode == .instruction) {
                    toggleCustom()
                }
            }
            .padding(.horizontal, 2).padding(.vertical, 1)
        }
    }

    private func selectableChip(icon: String, label: String, selected: Bool,
                                _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11))
                    .foregroundStyle(selected ? Theme.accentInk : Theme.textSecondary)
                Text(label).font(.system(size: 12.5))
                    .foregroundStyle(selected ? Theme.accentInk : Theme.textPrimary)
            }
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background {
                // Quiet translucent chip ON the composer's glass (a nested
                // material would fight the card); accent fill when selected.
                if selected { Capsule().fill(Theme.accent) }
                else { Capsule().fill(Theme.fillTranslucent.opacity(0.07)) }
            }
            .overlay {
                if !selected { Capsule().stroke(Theme.fillTranslucent.opacity(0.08), lineWidth: 1) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .opacity(isLoading ? 0.6 : 1)
        .fixedSize()
    }

    /// Select (or toggle off) an action — a pure selector. Nothing runs until the
    /// text is sent.
    private func selectAction(_ sel: SelectedAction) {
        composerMode = .text
        showSelectPrompt = false
        selectedAction = (selectedAction?.id == sel.id) ? nil : sel
    }

    private func toggleCustom() {
        selectedAction = nil
        composerMode = (composerMode == .instruction) ? .text : .instruction
    }

    private func shortcutKey(_ index: Int) -> KeyEquivalent {
        guard index < 9 else { return KeyEquivalent("0") }
        return KeyEquivalent(Character("\(index + 1)"))
    }

    // MARK: - Composer (Siri bottom bar: + · glass field · mic/send)

    /// One floating glass card: the field on top, the action chips, then the tool
    /// row — New · Chats · Settings · (space) · Dictate · Send ⏎.
    private var composer: some View {
        VStack(spacing: 10) {
            if showSelectPrompt && !draftIsEmpty { selectPrompt }
            composerField
            actionBar
            HStack(spacing: 8) {
                IconButton(systemName: "plus", size: 32,
                           disabled: thread.isEmpty && draft.isEmpty && selectedAction == nil && composerMode == .text,
                           help: "New chat") {
                    newChat()
                }
                IconButton(systemName: "clock.arrow.circlepath", size: 32, help: "Chats") { panel = .history }
                IconButton(systemName: "gearshape", size: 32, help: "Settings") { panel = .settings }
                Spacer(minLength: 4)
                IconButton(systemName: "mic.fill", size: 32, help: "Dictate") { enterVoiceMode() }
                sendControl
            }
        }
        .padding(14)
        .liquidGlass(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    /// The labeled primary action — Send ⏎, or Stop while streaming.
    private var sendControl: some View {
        Group {
            if isLoading {
                Button { currentTask?.cancel() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill").font(.system(size: 11, weight: .bold))
                        Text("Stop").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accentInk)
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(".", modifiers: .command)
            } else {
                Button { sendDraft() } label: {
                    HStack(spacing: 7) {
                        Text("Send").font(.system(size: 13, weight: .semibold))
                        Text("⏎").font(.system(size: 12, weight: .medium)).opacity(0.7)
                    }
                    .foregroundStyle(Theme.accentInk)
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(Capsule().fill(Theme.accent)
                        .shadow(color: Theme.accent.opacity(0.5), radius: 8, y: 2))
                }
                .buttonStyle(.plain)
                .disabled(draftIsEmpty)
                .opacity(draftIsEmpty ? 0.45 : 1)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    /// Nudge shown above the input when you try to send without picking an action.
    private var selectPrompt: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.turn.left.down").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Pick how to rewrite it below").font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 6)
            Button { sendAsIs() } label: {
                Text("Send as-is").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Theme.fillTranslucent.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.accent.opacity(0.4), lineWidth: 1))
    }

    /// Growing input (1→~4 lines, then scrolls). No pill of its own — it sits
    /// directly on the composer's glass; Send lives in the tool row below.
    private var composerField: some View {
        ZStack(alignment: .topLeading) {
            if draftIsEmpty {
                Text(composerPlaceholder)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textSecondary)
                    .allowsHitTesting(false)
            }
            ComposerTextView(text: Binding(get: { draft }, set: { draft = $0 }),
                             maxLines: 4,
                             onFocusChange: { composerFocused = $0 })
        }
        .padding(.horizontal, 4).padding(.top, 2)
        // Enter sends; Shift+Enter inserts a newline. A window-local key monitor
        // consumes Return before the field (or the window) can act on it.
        .background(SubmitKeyMonitor(onSubmit: { if !isLoading { sendDraft() } }))
    }

    private var composerPlaceholder: String {
        if composerMode == .instruction { return "Describe how to rewrite…  (⌘↩)" }
        if let sel = selectedAction { return "Type, then send to \(sel.label.lowercased())…" }
        return thread.isEmpty ? settings.mode.inputPlaceholder : "Add text or a reply…"
    }

    // MARK: - Chats panel (shared with the app window)

    /// The former "History" surface, now a browser of the shared saved
    /// conversations — the same chats the window shows, permanent (no 20-item cap).
    private var historyPanel: some View {
        let chats = store.conversations
        return Group {
            if chats.isEmpty {
                Text("No \(historyMode.title.capitalized) chats yet.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(chats) { chatRow($0) }
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
                    .background(OverlayScrollers())
                }
            }
        }
        .frame(maxHeight: .infinity)
        // The filter row floats as glass and the rows scroll UNDER it (and the
        // header), so there's no solid band at the top — same as the chat.
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                modeSegmented($historyMode, width: 200)
                Spacer(minLength: 6)
                Button { startNewChatFromList() } label: { miniCapsule("square.and.pencil", "New") }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .onAppear { historyMode = settings.mode }
    }

    private func chatRow(_ c: Conversation) -> some View {
        Button { openConversation(c) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(c.title.isEmpty ? "New chat" : c.title)
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if let preview = chatPreview(c) {
                    Text(preview).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassFloat(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu { Button("Delete", role: .destructive) { deleteConversation(c) } }
    }

    private func chatPreview(_ c: Conversation) -> String? {
        let text = c.turns.last(where: { $0.role == .assistant && !$0.text.isEmpty })?.text
            ?? c.turns.last(where: { $0.role == .user && !$0.text.isEmpty })?.text
        return text?.replacingOccurrences(of: "\n", with: " ")
    }

    /// Open a saved chat into the unified popover thread.
    private func openConversation(_ c: Conversation) {
        currentTask?.cancel(); isLoading = false
        let mode = c.mode.canonical
        settings.mode = mode
        currentConvoID[mode] = c.id
        threadByMode[mode] = c.turns
        selectedAction = nil; composerMode = .text; showSelectPrompt = false
        panel = .main
        injectWhatsNewIfNeeded()
    }

    private func startNewChatFromList() {
        newChat()
        panel = .main
        injectWhatsNewIfNeeded()
    }

    private func deleteConversation(_ c: Conversation) {
        store.delete(c.id)
        if currentConvoID[c.mode] == c.id {
            currentConvoID[c.mode] = nil
            threadByMode[c.mode] = []
        }
    }

    // MARK: - Derived

    private var latestUserText: String {
        for t in thread.reversed() where t.role == .user {
            return t.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
    private var draftIsEmpty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: - Shared conversation sync

    /// Persist the current mode's real turns into its shared conversation (creating
    /// one lazily on the first turn) so the window sees it. Ephemeral cards
    /// (What's New / setup) are never saved.
    private func syncCurrent() {
        let mode = settings.mode.canonical
        let turns = (threadByMode[mode] ?? []).filter { $0.role == .user || $0.role == .assistant }
        guard !turns.isEmpty else { return }
        let id = currentConvoID[mode] ?? {
            let fresh = UUID(); currentConvoID[mode] = fresh; return fresh
        }()
        var convo = store.conversations.first(where: { $0.id == id }) ?? Conversation(id: id, mode: mode, turns: [])
        convo.turns = turns
        convo.mode = mode
        store.save(convo)
    }

    // MARK: - Actions

    private func sendDraft() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if composerMode == .instruction {
            guard !latestUserText.isEmpty else { composerMode = .text; return }
            draft = ""; composerMode = .text
            run(systemPrompt: RewriteAction.customSystemPrompt(t), label: "Custom: \(t)")
            return
        }
        // Smart plain send (no explicit action): one decide-and-act pass that
        // either polishes text or fulfills a request.
        if selectedAction == nil && settings.smartIntent {
            addUserTurn(t)
            run(systemPrompt: "", label: "Improve", smart: true)
            return
        }
        // No explicit action picked → apply the unified default instead of
        // sending raw text that never gets rewritten.
        let sel = selectedAction ?? {
            let d = settings.mode.defaultAction
            return SelectedAction(id: d.id, systemPrompt: d.systemPrompt, label: d.label)
        }()
        addUserTurn(t)
        run(systemPrompt: sel.systemPrompt, label: sel.label)
    }

    /// Send the text as a plain note (no rewrite).
    private func sendAsIs() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { showSelectPrompt = false; return }
        addUserTurn(t)
    }

    private func addUserTurn(_ t: String) {
        thread.append(ChatTurn(role: .user, text: t, fromClipboard: fromClipboard))
        draft = ""; fromClipboard = false; showSelectPrompt = false
        syncCurrent()
    }

    /// Runs an action against the source text. When `smart` is set this is a Smart
    /// decide-and-act pass: the model both decides (polish vs. fulfill) and acts in
    /// one call, self-tagging its reply so the turn can be labeled (see streamBody).
    private func run(systemPrompt: String, label: String, variation: Bool = false,
                     source: String? = nil, wrap: Bool = true, smart: Bool = false) {
        let src = (source ?? latestUserText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else { return }
        let runMode = settings.mode.canonical
        currentTask?.cancel()
        isLoading = true

        // Smart uses its own single prompt and never wraps (it may legitimately
        // "answer" a request); the label is provisional until the tag resolves.
        let prompt = smart ? RewriteAction.smartSystemPrompt : systemPrompt
        let turn = ChatTurn(role: .assistant, text: "", actionLabel: label,
                            systemPrompt: prompt, isStreaming: true, sourceText: src,
                            fulfillsRequest: !wrap && !smart, isSmart: smart)
        let id = turn.id
        thread.append(turn)

        let provider = settings.makeProvider()
        // Smart sees the conversation so a follow-up is a refinement, not a new task.
        var payload: String
        if smart {
            payload = smartContextPayload() ?? src
        } else {
            payload = wrap ? RewriteAction.wrap(src) : src
        }
        if variation { payload += "\n\n(Give a noticeably different alternative version.)" }

        currentTask = Task {
            await streamBody(turnID: id, src: src, payload: payload,
                             systemPrompt: prompt, label: label,
                             runMode: runMode, provider: provider, parseSmartTag: smart)
        }
    }

    /// A transcript of the conversation so far for Smart, so a follow-up is read as
    /// a refinement/continuation of the previous answer rather than a new request.
    /// Returns nil when there's no prior context (the lone new message → use it raw).
    private func smartContextPayload() -> String? {
        let turns = thread.filter {
            ($0.role == .user || $0.role == .assistant)
            && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard turns.count > 1 else { return nil }   // only the new message → no context
        let transcript = turns
            .map { $0.role == .user ? "User: \($0.text)" : "You: \($0.text)" }
            .joined(separator: "\n\n")
        return """
        Below is the conversation so far. The final "User:" line is a new follow-up — treat it as a \
        continuation of this conversation (typically a refinement of, or addition to, what you last \
        wrote under "You:"), not a brand-new standalone task. Produce the updated result.

        \(transcript)
        """
    }

    /// Streams a provider response into an existing assistant turn, sharing the
    /// success / cancel / setup-card / error handling across every path. When
    /// `parseSmartTag` is set, the raw reply is accumulated in `rawText` and its
    /// leading [REWRITE]/[REQUEST] tag is stripped (and mapped to the turn label)
    /// as it streams, so `text` always holds clean, paste-ready output.
    private func streamBody(turnID id: UUID, src: String, payload: String,
                            systemPrompt: String, label: String,
                            runMode: RewriteMode, provider: any RewriteProvider,
                            parseSmartTag: Bool = false) async {
        do {
            let raw = try await provider.stream(text: payload, systemPrompt: systemPrompt) { piece in
                Task { @MainActor in
                    if parseSmartTag {
                        mutateTurn(id) {
                            $0.rawText += piece
                            let p = RewriteAction.parseSmart($0.rawText)
                            if let l = p.label { $0.actionLabel = l; $0.fulfillsRequest = (l == "Request") }
                            $0.text = p.body
                        }
                    } else {
                        mutateTurn(id) { $0.text += piece }
                    }
                }
            }
            let parsed: (label: String?, body: String) = parseSmartTag
                ? RewriteAction.parseSmart(raw)
                : (label: nil, body: RewriteAction.clean(raw))
            let result = parsed.body
            let finalLabel = parsed.label ?? label
            await MainActor.run {
                mutateTurn(id) {
                    $0.text = result; $0.isStreaming = false
                    if parseSmartTag {
                        $0.actionLabel = finalLabel
                        $0.fulfillsRequest = (parsed.label == "Request")
                    }
                }
                isLoading = false
                settings.addHistory(actionLabel: finalLabel, input: src, output: result, mode: runMode)
                syncCurrent()
                if settings.autoCopyResult { setClipboard(result) }
            }
        } catch {
            await MainActor.run {
                isLoading = false
                if Task.isCancelled {
                    thread.removeAll { $0.id == id && $0.text.isEmpty }
                    mutateTurn(id) { $0.isStreaming = false }
                    syncCurrent()
                } else if isSetupError(error) {
                    // Provider isn't set up — show an inline setup card instead
                    // of a raw error, and remember what to retry afterwards.
                    thread.removeAll { $0.id == id }
                    pendingRetry = PendingRun(systemPrompt: systemPrompt, label: label, source: src, smart: parseSmartTag)
                    if !thread.contains(where: { $0.role == .setup }) {
                        thread.append(ChatTurn(role: .setup, text: ""))
                    }
                } else {
                    mutateTurn(id) {
                        $0.text = error.localizedDescription
                        $0.isStreaming = false
                        $0.isError = true
                    }
                    syncCurrent()
                }
            }
        }
    }

    private func mutateTurn(_ id: UUID, _ change: (inout ChatTurn) -> Void) {
        if let i = thread.firstIndex(where: { $0.id == id }) { change(&thread[i]) }
    }

    /// True for "provider isn't configured" errors that the inline setup card can fix.
    private func isSetupError(_ error: Error) -> Bool {
        guard let re = error as? RewriteError else { return false }
        switch re {
        case .signedOut, .missingAPIKey, .ollamaUnreachable, .claudeCodeNotFound: return true
        default: return false
        }
    }

    /// Re-run the action that triggered the setup card, now that it's configured.
    private func retryPending() {
        guard let p = pendingRetry else { return }
        thread.removeAll { $0.role == .setup }
        pendingRetry = nil
        run(systemPrompt: p.systemPrompt, label: p.label, source: p.source, smart: p.smart)
    }

    private func dismissSetup(_ id: UUID) {
        thread.removeAll { $0.id == id }
        pendingRetry = nil
    }

    private func newChat() {
        currentTask?.cancel()
        isLoading = false
        thread = []
        currentConvoID[settings.mode] = nil   // next real turn starts a fresh shared chat
        draft = ""
        composerMode = .text
        selectedAction = nil
        pendingRetry = nil
        showSelectPrompt = false
        fromClipboard = false
        copiedTurnID = nil
    }

    // MARK: - Voice

    private func enterVoiceMode() {
        if !speech.isRecording { speech.toggle() }
        voiceMode = true
        // Dictation must stay on screen even if the user clicks away or switches
        // apps — ask the host to detach into a persistent floating panel.
        NotificationCenter.default.post(name: .rewriteVoiceActivated, object: nil)
    }

    private func finishVoice() {
        let captured = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if speech.isRecording { speech.stop() }
        voiceMode = false
        NotificationCenter.default.post(name: .rewriteVoiceEnded, object: nil)
        if !captured.isEmpty { draft = draft.isEmpty ? captured : draft + " " + captured }
        // The composer view is rebuilt on return from voice and re-focuses itself.
    }

    private func cancelVoice() {
        if speech.isRecording { speech.stop() }
        voiceMode = false
        NotificationCenter.default.post(name: .rewriteVoiceEnded, object: nil)
    }

    // MARK: - Clipboard

    private func autoFillFromClipboard() {
        guard settings.autoFillClipboard, thread.isEmpty, draft.isEmpty else { return }
        let pb = NSPasteboard.general
        guard pb.changeCount != lastClipboardCount else { return }
        lastClipboardCount = pb.changeCount
        if let s = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty, s.count <= 8000 {
            draft = s
            fromClipboard = true
        }
    }

    private func setClipboard(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

/// Reports the thread's natural content height so the invisible viewport can be
/// exactly as tall as the conversation (up to the cap).
struct ThreadHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Native multi-line composer input: a real NSScrollView + NSTextView so the
/// field scrolls with the trackpad (SwiftUI's TextField(axis:) only follows the
/// cursor). Grows from one line up to `maxLines`, then scrolls. Focus places the
/// cursor at the end (never select-all), which also defuses the tear-off
/// select-all. Enter is handled by SubmitKeyMonitor; Shift+Enter inserts a newline.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var maxLines: Int = 4
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ComposerScrollView {
        let tv = ComposerNSTextView()
        tv.delegate = context.coordinator
        tv.string = text
        tv.font = .systemFont(ofSize: 13.5)
        tv.textColor = Theme.nsTextPrimary   // dynamic NSColor — tracks the window's appearance
        tv.insertionPointColor = NSColor(Theme.accent)
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.onFocusChange = onFocusChange

        let scroll = ComposerScrollView()
        scroll.maxLines = maxLines
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.documentView = tv
        // Fill the available width but hold height to the intrinsic (capped) size.
        scroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scroll.setContentHuggingPriority(.defaultHigh, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        context.coordinator.scrollView = scroll
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: ComposerScrollView, context: Context) {
        context.coordinator.parent = self
        scroll.maxLines = maxLines
        guard let tv = scroll.documentView as? ComposerNSTextView else { return }
        tv.onFocusChange = onFocusChange
        if tv.string != text {
            tv.string = text
            tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        // Recompute height once SwiftUI has settled the width (so wrapping — and
        // thus line count — is correct, e.g. for clipboard-prefilled drafts).
        scroll.invalidateIntrinsicContentSize()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var scrollView: ComposerScrollView?
        weak var textView: ComposerNSTextView?

        init(_ parent: ComposerTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            if parent.text != tv.string { parent.text = tv.string }
            scrollView?.invalidateIntrinsicContentSize()
        }
    }
}

/// NSTextView that focuses itself when shown, never selects-all on focus (cursor
/// to the end), and reports focus changes back to SwiftUI.
final class ComposerNSTextView: NSTextView {
    var onFocusChange: (Bool) -> Void = { _ in }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // Focus on appear — covers first open and the rebuild after voice/settings.
        DispatchQueue.main.async { [weak self] in
            guard let self, let win = self.window else { return }
            win.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            let end = (string as NSString).length
            setSelectedRange(NSRange(location: end, length: 0))   // never select-all
            DispatchQueue.main.async { [weak self] in self?.onFocusChange(true) }
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { DispatchQueue.main.async { [weak self] in self?.onFocusChange(false) } }
        return ok
    }

    /// Esc dismisses the floating glass surface. The composer holds first
    /// responder on every show, and NSTextView otherwise swallows Esc into
    /// word-completion — so `.onExitCommand` never fires. Intercept it here.
    /// (In the main window the panel isn't showing, so this is a harmless no-op.)
    override func cancelOperation(_ sender: Any?) {
        NotificationCenter.default.post(name: .rewriteCloseWindow, object: nil)
    }
}

/// Scroll view that sizes itself to its text, from one line up to `maxLines`
/// (then it scrolls), so SwiftUI lays the composer out at the right height.
final class ComposerScrollView: NSScrollView {
    var maxLines: Int = 4

    override var intrinsicContentSize: NSSize {
        guard let tv = documentView as? NSTextView,
              let lm = tv.layoutManager, let tc = tv.textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 20)
        }
        lm.ensureLayout(for: tc)
        let line = lm.defaultLineHeight(for: tv.font ?? .systemFont(ofSize: 13.5))
        let used = lm.usedRect(for: tc).height
        let h = min(max(used, line), line * CGFloat(maxLines))
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(h))
    }
}

/// Forces the enclosing SwiftUI `ScrollView`'s underlying NSScrollView to use thin
/// overlay scrollers (appear only while scrolling, then fade) instead of the wide
/// always-on bar — regardless of the system "show scroll bars" setting.
struct OverlayScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let s = v.enclosingScrollView else { return }
            s.scrollerStyle = .overlay
            s.hasHorizontalScroller = false
            s.autohidesScrollers = true
        }
    }
}

/// Zero-size helper that installs a window-local key monitor so the composer's own
/// keys drive it — reliably, even inside a docked NSPopover, where these keys
/// otherwise leak past the field and dismiss the popover (SwiftUI's `.onKeyPress`
/// doesn't consume them). Plain Return sends; Shift+Return inserts a newline; a
/// plain Space types a space — all handled and consumed here so none of them can
/// reach the popover and close it. Every other key falls through untouched. The
/// monitor lives only while this view is on screen.
struct SubmitKeyMonitor: NSViewRepresentable {
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.hostView = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onSubmit = onSubmit
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSubmit: onSubmit) }

    final class Coordinator {
        var onSubmit: () -> Void
        weak var hostView: NSView?
        private var monitor: Any?

        init(onSubmit: @escaping () -> Void) { self.onSubmit = onSubmit }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                // Return (36) / keypad Enter (76) / Space (49) while THIS surface's
                // composer is focused. The monitor is app-wide, and the popover and
                // the main window now both have a composer, so we must scope to our
                // OWN window (event.window === hostView.window) or Return could fire
                // the other surface's send. We act before window dispatch and CONSUME.
                guard event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49,
                      let host = self.hostView, event.window === host.window,
                      let tv = event.window?.firstResponder as? ComposerNSTextView
                else { return event }
                // Mid-IME composition: let the input method handle the key (e.g. Return
                // confirms the candidate). Don't act on it and don't consume it.
                if tv.hasMarkedText() { return event }
                switch event.keyCode {
                case 49:
                    // Plain Space only — leave ⌥/⌃/⌘+Space (e.g. the open hotkey) alone.
                    guard event.modifierFlags
                        .intersection([.command, .option, .control, .function]).isEmpty
                    else { return event }
                    tv.insertText(" ", replacementRange: tv.selectedRange())
                default:  // Return / keypad Enter
                    if event.modifierFlags.contains(.shift) {
                        tv.insertNewline(nil)   // Shift+Return → newline
                    } else {
                        self.onSubmit()         // Return → send (caller gates on !isLoading)
                    }
                }
                return nil
            }
        }

        func remove() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        }

        deinit { remove() }
    }
}

/// Inline card shown in the chat when the chosen provider needs setup. Lets the
/// user pick a provider and (for Free models) sign in with an email code without
/// leaving the chat, then retry the action that failed.
struct SetupCardView: View {
    var onReady: () -> Void
    var onDismiss: () -> Void
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 14)).foregroundStyle(Theme.accent)
                Text("Set up a model").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }.buttonStyle(.plain).help("Dismiss")
            }

            Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 2) {
                ForEach(LLMProvider.allCases) { providerRow($0) }
            }

            if settings.provider == .hosted && !settings.isSignedInToHosted {
                HostedSignInView()
            } else if needsKey {
                Text("Add your Claude API key in Settings → Claude to use this provider.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isReady {
                Button { onReady() } label: { Text("Try again") }
                    .buttonStyle(InstrumentButtonStyle(prominent: true))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(RoundedRectangle(cornerRadius: Metric.bubbleRadius, style: .continuous))
        .padding(.trailing, 8)
    }

    private func providerRow(_ p: LLMProvider) -> some View {
        Button { settings.provider = p } label: {
            HStack(spacing: 8) {
                Image(systemName: settings.provider == p ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(settings.provider == p ? Theme.accent : Theme.textSecondary)
                Text(p.displayName).font(.system(size: 12.5)).foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var isReady: Bool {
        switch settings.provider {
        case .appleOnDevice:       return AppleOnDeviceProvider.isAvailable
        case .hosted:              return settings.isSignedInToHosted
        case .anthropic:           return !settings.apiKey.isEmpty
        case .claudeCode, .ollama: return true
        }
    }

    private var needsKey: Bool {
        settings.provider == .anthropic && settings.apiKey.isEmpty
    }

    private var subtitle: String {
        if settings.provider == .hosted && !settings.isSignedInToHosted {
            return "Free models need a quick email sign-in (it adds you to the newsletter). Or choose another provider below."
        }
        if settings.provider == .appleOnDevice && !AppleOnDeviceProvider.isAvailable {
            return "Built-in AI isn't available on this Mac. Pick another provider below."
        }
        return "Choose a model provider to continue — you can change it anytime in Settings."
    }
}

/// Friendly "what's new" card populated into the chat after an update — a quick,
/// fun tour of what moved and how to use it.
struct WhatsNewCardView: View {
    var onDismiss: () -> Void

    private struct Highlight: Identifiable {
        let id = UUID(); let icon: String; let title: String; let blurb: String
    }

    private let highlights: [Highlight] = [
        .init(icon: "macwindow", title: "A full app window",
              blurb: "Open Rewrite as a resizable app from the Dock or Launchpad, with a conversations sidebar — your chats are saved and you pick up right where you left off."),
        .init(icon: "sparkles", title: "Smart does the right thing",
              blurb: "Smart now recognizes whether you pasted text to polish or a request to carry out, then takes the appropriate path without making you choose a mode."),
        .init(icon: "sidebar.left", title: "Chats, kept tidy",
              blurb: "All Rewrite chats live together in one saved list, so you can pick up any conversation from the menu bar or the full window."),
        .init(icon: "gearshape", title: "Settings within reach",
              blurb: "Providers, your API key, models and presets are one click away — in the menu bar and at the bottom of the app's sidebar.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 14)).foregroundStyle(Theme.accent)
                Text("What's new in \(AppUpdater.shared.currentVersion)")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }.buttonStyle(.plain).help("Dismiss")
            }

            Text("A few new things since your last update. Here's the quick tour:")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(highlights) { h in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: h.icon).font(.system(size: 13)).foregroundStyle(Theme.accent)
                            .frame(width: 20, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.title).font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(h.blurb).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(RoundedRectangle(cornerRadius: Metric.bubbleRadius, style: .continuous))
        .padding(.trailing, 8)
    }
}

/// iMessage-style "typing…" indicator: three dots that bounce in a staggered loop.
/// Shown in the assistant bubble while waiting for the first words of a response.
struct TypingDots: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.textSecondary)
                    .frame(width: 6, height: 6)
                    .offset(y: animating ? -3 : 0)
                    .opacity(animating ? 1 : 0.45)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.18), value: animating)
            }
        }
        .onAppear { animating = true }
        .accessibilityLabel("Working…")
    }
}
