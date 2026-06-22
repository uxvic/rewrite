import SwiftUI
import AppKit

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
}

/// What the composer's text means when sent: new source text, or a one-off
/// custom instruction to run on the latest source.
enum ComposerMode { case text, instruction }

/// An action picked from the action bar, applied to text when it's sent.
struct SelectedAction: Equatable { let id: String; let systemPrompt: String; let label: String }

/// A run to re-attempt after the user finishes provider setup in the chat.
struct PendingRun: Equatable { let systemPrompt: String; let label: String; let source: String }

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
            }
        }
        .frame(width: 380, height: 668)
        .ambientBackground()
        .onAppear { autoFillFromClipboard(); injectWhatsNewIfNeeded(); DispatchQueue.main.async { composerFocused = true } }
        .onChange(of: settings.mode) { _, _ in selectedAction = nil; composerMode = .text; showSelectPrompt = false; injectWhatsNewIfNeeded() }
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
                modePill
            } else {
                Text(panel == .settings ? "Settings" : "History")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            }
            Spacer(minLength: 6)
            IconButton(systemName: panel == .settings ? "chevron.left" : "gearshape",
                       active: panel == .settings, help: "Settings") {
                panel = (panel == .settings) ? .main : .settings
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    /// Soft segmented WRITING / PROMPT pill.
    private var modePill: some View {
        HStack(spacing: 0) {
            ForEach(RewriteMode.allCases) { m in
                let active = settings.mode == m
                Text(m.title.capitalized)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(active ? Theme.accentInk : Theme.textSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background {
                        if active { Capsule().fill(Theme.accent) }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { settings.mode = m } }
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.fillTranslucent.opacity(0.06)))
        .overlay(Capsule().stroke(Theme.fillTranslucent.opacity(0.08), lineWidth: 1))
        .frame(width: 200)
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
                run(systemPrompt: turn.systemPrompt, label: turn.actionLabel, variation: true, source: turn.sourceText)
            }
            miniButton(turn.showingDiff ? "text.alignleft" : "plus.forwardslash.minus",
                       turn.showingDiff ? "Result" : "Diff") {
                mutateTurn(turn.id) { $0.showingDiff.toggle() }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Recent rewrites")
                Spacer()
                if !settings.history.isEmpty {
                    Button { settings.history = [] } label: { Text("Clear") }
                        .buttonStyle(InstrumentButtonStyle()).controlSize(.mini)
                }
            }
            if settings.history.isEmpty {
                Text("Your recent rewrites will appear here.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        historyGroup("Writing", items: settings.history.filter { $0.mode == .writing })
                        historyGroup("Prompt", items: settings.history.filter { $0.mode == .prompt })
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity)
    }

    /// One labelled history section ("Writing" / "Prompt"), hidden when empty.
    @ViewBuilder
    private func historyGroup(_ title: String, items: [HistoryItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(1)
                    .foregroundStyle(Theme.textSecondary)
                ForEach(items) { historyRow($0) }
            }
        }
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

    private func run(systemPrompt: String, label: String, variation: Bool = false, source: String? = nil) {
        let src = (source ?? latestUserText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else { return }
        let runMode = settings.mode   // tag history with the mode this rewrite belongs to
        currentTask?.cancel()
        isLoading = true

        let turn = ChatTurn(role: .assistant, text: "", actionLabel: label,
                            systemPrompt: systemPrompt, isStreaming: true, sourceText: src)
        let id = turn.id
        thread.append(turn)

        let provider = settings.makeProvider()
        var payload = RewriteAction.wrap(src)
        if variation { payload += "\n\n(Give a noticeably different alternative version.)" }

        currentTask = Task {
            do {
                let raw = try await provider.stream(text: payload, systemPrompt: systemPrompt) { piece in
                    Task { @MainActor in mutateTurn(id) { $0.text += piece } }
                }
                let result = RewriteAction.clean(raw)
                await MainActor.run {
                    mutateTurn(id) { $0.text = result; $0.isStreaming = false }
                    isLoading = false
                    settings.addHistory(actionLabel: label, input: src, output: result, mode: runMode)
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
                        pendingRetry = PendingRun(systemPrompt: systemPrompt, label: label, source: src)
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
        run(systemPrompt: p.systemPrompt, label: p.label, source: p.source)
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
    }

    private func finishVoice() {
        let captured = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if speech.isRecording { speech.stop() }
        voiceMode = false
        guard !captured.isEmpty else { return }
        draft = draft.isEmpty ? captured : draft + " " + captured
    }

    private func cancelVoice() {
        if speech.isRecording { speech.stop() }
        voiceMode = false
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

            Button { onDismiss() } label: { Text("Try it") }
                .buttonStyle(InstrumentButtonStyle(prominent: true))
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
