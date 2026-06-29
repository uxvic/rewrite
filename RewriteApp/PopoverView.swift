import SwiftUI
import AppKit
import Combine

/// One message in the rewrite conversation. User turns hold the source text;
/// assistant turns hold a rewrite (streamed in) plus the action that produced it.
struct ChatTurn: Identifiable, Equatable {
    enum Role { case user, assistant, setup, whatsNew }
    let id = UUID()
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
    @State private var draftByMode: [RewriteMode: String] = [:]
    @State private var composerMode: ComposerMode = .text
    @State private var selectedAction: SelectedAction?
    @State private var pendingRetry: PendingRun?
    @State private var showSelectPrompt = false
    @State private var isLoading = false
    @State private var currentTask: Task<Void, Never>?
    @State private var copiedTurnID: UUID?
    @FocusState private var composerFocused: Bool
    @State private var voiceMode = false
    @State private var fromClipboard = false
    @State private var lastClipboardCount = -1

    private enum Panel { case main, settings, history }
    @State private var panel: Panel = .main

    /// Which mode's rewrites the History panel is showing (its own Writing/Prompt
    /// tab, independent of the chat's active mode).
    @State private var historyMode: RewriteMode = .writing

    /// Writing and Prompt keep separate conversations + drafts, keyed by mode,
    /// so switching tabs never mixes their messages.
    private var thread: [ChatTurn] {
        get { threadByMode[settings.mode] ?? [] }
        nonmutating set { threadByMode[settings.mode] = newValue }
    }
    private var draft: String {
        get { draftByMode[settings.mode] ?? "" }
        nonmutating set { draftByMode[settings.mode] = newValue }
    }

    var body: some View {
        Group {
            if voiceMode {
                VoiceOverlayView(speech: speech, onDone: finishVoice, onCancel: cancelVoice)
            } else {
                VStack(spacing: 0) {
                    specBar
                    HairlineDivider()
                    Group {
                        switch panel {
                        case .main:     chatPanel
                        case .settings: SettingsView()
                        case .history:  historyPanel
                        }
                    }
                }
                // Esc dismisses a torn-off floating window (no-op while docked).
                .onExitCommand { NotificationCenter.default.post(name: .rewriteCloseWindow, object: nil) }
            }
        }
        .frame(width: 380, height: 668)
        .ambientBackground()
        .onAppear { autoFillFromClipboard(); injectWhatsNewIfNeeded(); DispatchQueue.main.async { composerFocused = true } }
        .onChange(of: settings.mode) { _, _ in selectedAction = nil; composerMode = .text; showSelectPrompt = false; injectWhatsNewIfNeeded() }
        // Host is dismissing a torn-off window while dictation is live — end it
        // cleanly so the mic is released.
        .onReceive(NotificationCenter.default.publisher(for: .rewriteForceExitVoice)) { _ in
            if voiceMode { cancelVoice() }
        }
        // Opened from the menu-bar "Settings…" item.
        .onReceive(NotificationCenter.default.publisher(for: .rewriteShowSettings)) { _ in
            voiceMode = false
            panel = .settings
        }
    }

    // MARK: - Header

    /// Compact one-row header: History (left) · mode pill (center) · Settings (right).
    private var specBar: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "clock.arrow.circlepath", active: panel == .history, help: "History") {
                panel = (panel == .history) ? .main : .history
            }
            Spacer(minLength: 6)
            if panel == .main {
                modeSegmented($settings.mode, width: 200)
            } else {
                Text(panel == .settings ? "Settings" : "History")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            }
            Spacer(minLength: 6)
            // Settings now lives in the menu-bar menu; this top-right control is a
            // Close (✕) that dismisses the window — except inside Settings, where
            // it's a Back chevron returning to the chat.
            IconButton(systemName: panel == .settings ? "chevron.left" : "xmark",
                       active: panel == .settings,
                       help: panel == .settings ? "Back" : "Close") {
                if panel == .settings {
                    panel = .main
                } else {
                    NotificationCenter.default.post(name: .rewriteCloseWindow, object: nil)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        // Drag the header to tear the window off the menu bar into a floating,
        // movable panel. Taps on the buttons/pill still win (minimumDistance).
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { _ in NotificationCenter.default.post(name: .rewriteWindowDragChanged, object: nil) }
                .onEnded { _ in NotificationCenter.default.post(name: .rewriteWindowDragEnded, object: nil) }
        )
    }

    /// Soft segmented WRITING / PROMPT pill, bound to any mode selection so it can
    /// drive both the chat header and the History filter.
    private func modeSegmented(_ selection: Binding<RewriteMode>, width: CGFloat = 200) -> some View {
        HStack(spacing: 0) {
            ForEach(RewriteMode.allCases) { m in
                let active = selection.wrappedValue == m
                Text(m.title.capitalized)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(active ? Theme.accentInk : Theme.textSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background {
                        if active { Capsule().fill(Theme.accent) }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { selection.wrappedValue = m } }
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.fillTranslucent.opacity(0.06)))
        .overlay(Capsule().stroke(Theme.fillTranslucent.opacity(0.08), lineWidth: 1))
        .frame(width: width)
    }

    // MARK: - Chat panel

    private var chatPanel: some View {
        VStack(spacing: 0) {
            threadView
            composer
        }
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

    private var threadView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if thread.isEmpty {
                        emptyState
                    } else {
                        ForEach(thread) { turn in turnView(turn) }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .frame(maxHeight: .infinity)
            .onChange(of: thread) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.bubble").font(.system(size: 26)).foregroundStyle(Theme.textSecondary)
            Text(settings.mode == .writing
                 ? "Paste, type, or dictate the text you want to rework — then pick how to rewrite it."
                 : "Paste a rough prompt — then pick how to improve it.")
                .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 40).padding(.horizontal, 18)
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
                .background(RoundedRectangle(cornerRadius: Metric.bubbleRadius, style: .continuous).fill(Theme.panel))
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
                    .background(RoundedRectangle(cornerRadius: Metric.bubbleRadius, style: .continuous).fill(Theme.surface))
            } else {
                bodyText(turn)
                    .font(.system(size: 13.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: Metric.bubbleRadius, style: .continuous).fill(Theme.surface))
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
            miniButton("arrow.clockwise", "Retry") {
                run(systemPrompt: turn.systemPrompt, label: turn.actionLabel,
                    variation: true, source: turn.sourceText,
                    wrap: !turn.fulfillsRequest, smart: turn.isSmart)
            }
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
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Theme.fillTranslucent.opacity(0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action bar (pick an action, then type & send)

    /// Horizontal, scrollable row of actions under the composer. Tap to select;
    /// the selected action is applied to the text when it's sent.
    private var actionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                // Writing only: toggle whether a plain send classifies intent
                // (rewrite vs. fulfill) before acting. Governs the default send;
                // explicit actions below always rewrite literally.
                if settings.mode == .writing {
                    selectableChip(icon: "sparkles", label: "Smart",
                                   selected: settings.smartIntent) {
                        settings.smartIntent.toggle()
                    }
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
            .background(Capsule().fill(selected ? Theme.accent : Theme.fillTranslucent.opacity(0.06)))
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

    private var composer: some View {
        VStack(spacing: 8) {
            if showSelectPrompt && !draftIsEmpty { selectPrompt }
            HStack(alignment: .bottom, spacing: 8) {
                IconButton(systemName: "plus", size: 34,
                           disabled: thread.isEmpty && draft.isEmpty && selectedAction == nil && composerMode == .text,
                           help: "New chat") {
                    newChat()
                }
                composerField
                IconButton(systemName: "mic.fill", size: 34, help: "Dictate") { enterVoiceMode() }
            }
            actionBar
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
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
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.fillTranslucent.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.accent.opacity(0.4), lineWidth: 1))
    }

    /// Growing pill input (1→~4 lines, then scrolls) with the send button inside.
    private var composerField: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField(composerPlaceholder,
                      text: Binding(get: { draft }, set: { draft = $0 }),
                      axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1...4)
                .focused($composerFocused)
                // Enter sends; Shift+Enter inserts a newline. (The field is
                // multi-line, so a plain Return would otherwise just add a line.)
                .onKeyPress(.return) { press in
                    if press.modifiers.contains(.shift) { return .ignored }
                    if isLoading || draftIsEmpty { return .ignored }
                    sendDraft()
                    return .handled
                }
                .padding(.leading, 10)
                .padding(.vertical, 4)
            if isLoading {
                insideButton("stop.fill") { currentTask?.cancel() }
                    .keyboardShortcut(".", modifiers: .command)
            } else if !draftIsEmpty {
                insideButton("arrow.up") { sendDraft() }
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 5).padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 21, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(composerBorder, lineWidth: 1))
    }

    /// The send / stop button that lives inside the input pill.
    private func insideButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.accentInk)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.accent))
        }
        .buttonStyle(.plain)
    }

    private var composerBorder: Color {
        (composerMode == .instruction || composerFocused)
            ? Theme.accent.opacity(0.6) : Theme.fillTranslucent.opacity(0.08)
    }

    private var composerPlaceholder: String {
        if composerMode == .instruction { return "Describe how to rewrite…  (⌘↩)" }
        if let sel = selectedAction { return "Type, then send to \(sel.label.lowercased())…" }
        return thread.isEmpty ? settings.mode.inputPlaceholder : "Add text or a reply…"
    }

    // MARK: - History panel

    private var historyPanel: some View {
        let items = settings.history.filter { $0.mode == historyMode }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                modeSegmented($historyMode, width: 200)
                Spacer(minLength: 6)
                if !settings.history.isEmpty {
                    Button { settings.history = [] } label: { Text("Clear") }
                        .buttonStyle(InstrumentButtonStyle()).controlSize(.mini)
                }
            }
            if items.isEmpty {
                Text("No \(historyMode.title.capitalized) rewrites yet.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(items) { historyRow($0) }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity)
        .onAppear { historyMode = settings.mode }
    }

    private func historyRow(_ item: HistoryItem) -> some View {
        Button { openHistory(item) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.actionLabel)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                Text(item.output).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .module(Theme.panel)
        }
        .buttonStyle(.plain)
    }

    private func openHistory(_ item: HistoryItem) {
        settings.mode = item.mode   // open in the matching tab; computed thread targets it
        newChat()
        thread.append(ChatTurn(role: .user, text: item.input))
        thread.append(ChatTurn(role: .assistant, text: item.output,
                               actionLabel: item.actionLabel, sourceText: item.input))
        panel = .main
    }

    // MARK: - Derived

    private var latestUserText: String {
        for t in thread.reversed() where t.role == .user {
            return t.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
    private var draftIsEmpty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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
        // Smart plain send (Writing, no explicit action): one decide-and-act pass
        // that polishes text or fulfills a request, labeled once it self-tags.
        if selectedAction == nil && settings.mode == .writing && settings.smartIntent {
            addUserTurn(t)
            run(systemPrompt: "", label: "Improve", smart: true)
            return
        }
        // No explicit action picked → apply the mode's sensible default
        // (Writing: fix grammar + light polish; Prompt: optimize) instead of
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
    }

    /// Runs an action against the source text. When `smart` is set this is a Smart
    /// decide-and-act pass: the model both decides (polish vs. fulfill) and acts in
    /// one call, self-tagging its reply so the turn can be labeled (see streamBody).
    private func run(systemPrompt: String, label: String, variation: Bool = false,
                     source: String? = nil, wrap: Bool = true, smart: Bool = false) {
        let src = (source ?? latestUserText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else { return }
        let runMode = settings.mode   // tag history with the mode this rewrite belongs to
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
        var payload = (wrap && !smart) ? RewriteAction.wrap(src) : src
        if variation { payload += "\n\n(Give a noticeably different alternative version.)" }

        currentTask = Task {
            await streamBody(turnID: id, src: src, payload: payload,
                             systemPrompt: prompt, label: label,
                             runMode: runMode, provider: provider, parseSmartTag: smart)
        }
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
                if settings.autoCopyResult { setClipboard(result) }
            }
        } catch {
            await MainActor.run {
                isLoading = false
                if Task.isCancelled {
                    thread.removeAll { $0.id == id && $0.text.isEmpty }
                    mutateTurn(id) { $0.isStreaming = false }
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
        if !captured.isEmpty { draft = draft.isEmpty ? captured : draft + " " + captured }
        // The reused window won't re-fire .onAppear, so re-focus the composer.
        DispatchQueue.main.async { composerFocused = true }
    }

    private func cancelVoice() {
        if speech.isRecording { speech.stop() }
        voiceMode = false
        DispatchQueue.main.async { composerFocused = true }
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
        .module(Theme.surface)
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
        .init(icon: "rectangle.split.2x1", title: "Writing & Prompt, kept apart",
              blurb: "Each tab keeps its own conversation and history now — switching never mixes them up."),
        .init(icon: "wand.and.stars", title: "Just hit send",
              blurb: "Send without picking a style and Rewrite fixes grammar and polishes for you — Prompt mode optimizes."),
        .init(icon: "lock.shield", title: "Your data, your call",
              blurb: "Sign-in stays optional, and you can delete your account and data anytime from Settings."),
        .init(icon: "text.bubble", title: "What's new, right here",
              blurb: "Release notes now land straight in the chat — no extra windows to chase.")
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
        .module(Theme.surface)
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
