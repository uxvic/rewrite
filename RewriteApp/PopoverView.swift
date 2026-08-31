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
    @ObservedObject private var clipboard = ClipboardStore.shared
    @StateObject private var speech = SpeechManager()

    @State private var threadByMode: [RewriteMode: [ChatTurn]] = [:]
    // Rewrite is one continuous conversation. This dictionary remains in place
    // for now to avoid disrupting the streaming mutation helpers below, but it
    // is always addressed through the canonical unified mode.
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
    private enum WorkspaceTab: CaseIterable {
        case rewrite
        case clipboard

        var title: String {
            switch self {
            case .rewrite: "Rewrite"
            case .clipboard: "Clipboard"
            }
        }

        var systemImage: String {
            switch self {
            case .rewrite: "sparkles"
            case .clipboard: "clipboard"
            }
        }
    }
    @State private var panel: Panel = .main
    @State private var workspaceTab: WorkspaceTab = .rewrite

    private var thread: [ChatTurn] {
        get { threadByMode[.rewrite] ?? [] }
        nonmutating set { threadByMode[.rewrite] = newValue }
    }

    var body: some View {
        Group {
            if voiceMode {
                VoiceOverlayView(speech: speech, onDone: finishVoice, onCancel: cancelVoice)
            } else {
                // The header and composer float as glass; the content scrolls
                // full-height UNDER them (safe-area insets), so the chat shows
                // through and behind the glass instead of stopping at a solid bar.
                Group {
                    switch panel {
                    case .main:
                        workspaceContent
                    case .settings: SettingsView()
                    case .history:  historyPanel
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) { specBar }
                // Esc dismisses a torn-off floating window (no-op while docked).
                .onExitCommand { NotificationCenter.default.post(name: .rewriteCloseWindow, object: nil) }
            }
        }
        .frame(width: 380, height: 668)
        .quickSurfaceBackground()
        .onAppear { autoFillFromClipboard(); injectWhatsNewIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .rewritePanelWillShow)) { _ in
            autoFillFromClipboard()
            injectWhatsNewIfNeeded()
        }
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

    // MARK: - Header

    /// Compact floating header: rewrite/history controls stay available while the
    /// two product destinations share one visual shell.
    private var specBar: some View {
        GlassGroup {
            HStack(spacing: 8) {
                IconButton(systemName: "clock.arrow.circlepath", active: panel == .history, help: "History") {
                    panel = (panel == .history) ? .main : .history
                }
                Spacer(minLength: 6)
                if panel == .main {
                    workspaceTabs
                } else {
                    Text(panel == .settings ? "Settings" : "History")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .glassFloat(Capsule())
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

    /// A small native-feeling destination switcher. This replaces the old
    /// Writing/Prompt control: Rewrite is the unified assistant, Clipboard is a
    /// first-class surface whose private local capture layer follows next.
    private var workspaceTabs: some View {
        HStack(spacing: 0) {
            ForEach(WorkspaceTab.allCases, id: \.self) { tab in
                let active = workspaceTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        workspaceTab = tab
                        selectedAction = nil
                        composerMode = .text
                        showSelectPrompt = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.systemImage).font(.system(size: 10.5, weight: .semibold))
                        Text(tab.title).font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background {
                        if active {
                            Capsule().fill(Theme.fillTranslucent.opacity(0.12))
                                .overlay(Capsule().stroke(Theme.fillTranslucent.opacity(0.10), lineWidth: 1))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glassFloat(Capsule())
        .frame(width: 218)
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
                .background(OverlayScrollers())
            }
            .frame(maxHeight: .infinity)
            .onChange(of: thread) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch workspaceTab {
        case .rewrite:
            threadView.safeAreaInset(edge: .bottom, spacing: 0) { composer }
        case .clipboard:
            clipboardPanel
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.bubble").font(.system(size: 26)).foregroundStyle(Theme.textSecondary)
            Text("Paste, type, or dictate text to rework. You can also ask Rewrite to draft something new.")
                .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 40).padding(.horizontal, 18)
    }

    private var clipboardPanel: some View {
        Group {
            if clipboard.items.isEmpty {
                clipboardEmptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(clipboard.items) { item in
                            clipboardRow(item)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
                    .background(OverlayScrollers())
                }
                .safeAreaInset(edge: .top, spacing: 0) { clipboardHistoryHeader }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var clipboardEmptyState: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(Theme.fillTranslucent.opacity(0.08)).frame(width: 64, height: 64)
                Image(systemName: settings.clipboardHistoryEnabled ? "clipboard" : "clipboard.slash")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            VStack(spacing: 7) {
                Text(settings.clipboardHistoryEnabled ? "Clipboard history" : "Clipboard history is paused")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(settings.clipboardHistoryEnabled
                     ? "Copy text anywhere on your Mac and it will appear here."
                     : "Turn Clipboard History back on in Settings when you are ready to capture again.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.system(size: 11, weight: .semibold))
                Text("Stored only on this Mac")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .adaptiveGlass(Capsule())
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 34)
    }

    private var clipboardHistoryHeader: some View {
        HStack {
            Text("Clipboard history")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .glassFloat(Capsule())
            Spacer(minLength: 6)
            Button("Clear") { clipboard.clear() }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .glassFloat(Capsule())
                .buttonStyle(.plain)
                .help("Clear clipboard history")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func clipboardRow(_ item: ClipboardItem) -> some View {
        Button { useClipboardItem(item) } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 18, height: 20)
                VStack(alignment: .leading, spacing: 5) {
                    Text(clipboardPreview(item.text))
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        Text(clipboardTimestamp(item.createdAt))
                        Text("•")
                        Text("Use in Rewrite")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 6)
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassFloat(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Use in Rewrite") { useClipboardItem(item) }
            Button("Copy") { setClipboard(item.text) }
            Divider()
            Button("Remove", role: .destructive) { clipboard.remove(item) }
        }
    }

    private func useClipboardItem(_ item: ClipboardItem) {
        draft = draftIsEmpty ? item.text : draft + "\n\n" + item.text
        fromClipboard = true
        selectedAction = nil
        composerMode = .text
        showSelectPrompt = false
        workspaceTab = .rewrite
    }

    private func clipboardPreview(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clipboardTimestamp(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
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

    /// The short action rail keeps the high-frequency choices in reach. Everything
    /// else lives under Actions, rather than turning the composer into a long row
    /// of equally weighted controls.
    private var actionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                // Smart governs a plain send: it either lightly improves existing
                // text or fulfills a writing request. A chosen action is a one-send
                // override, so it intentionally clears Smart's highlight.
                selectableChip(icon: "sparkles", label: "Smart",
                               selected: settings.smartIntent && selectedAction == nil && composerMode == .text) {
                    let smartActive = settings.smartIntent && selectedAction == nil && composerMode == .text
                    selectedAction = nil
                    composerMode = .text
                    showSelectPrompt = false
                    settings.smartIntent = !smartActive
                }
                ForEach(Array(directActions.enumerated()), id: \.element.id) { idx, action in
                    selectableChip(icon: action.systemImage, label: action.label,
                                   selected: selectedAction?.id == action.id) {
                        selectAction(SelectedAction(id: action.id, systemPrompt: action.systemPrompt, label: action.label))
                    }
                    .keyboardShortcut(shortcutKey(idx), modifiers: .command)
                }
                actionsMenu
            }
            .padding(.horizontal, 2).padding(.vertical, 1)
        }
    }

    /// Improve, paraphrase, and grammar are the visible one-tap transforms. Smart
    /// sits beside them as the default conversational action.
    private var directActions: [PresetAction] {
        [
            RewriteMode.rewrite.defaultAction,
            presetAction(for: .paraphrase),
            presetAction(for: .grammar)
        ]
    }

    private var additionalActions: [PresetAction] {
        let directIDs = Set(directActions.map(\.id))
        return RewriteMode.rewrite.actions.filter { !directIDs.contains($0.id) }
    }

    private func presetAction(for action: RewriteAction) -> PresetAction {
        PresetAction(id: action.id, label: action.label,
                     systemImage: action.systemImage, systemPrompt: action.systemPrompt)
    }

    private var actionsMenu: some View {
        let moreSelected = composerMode == .instruction
            || additionalActions.contains { $0.id == selectedAction?.id }
            || settings.customPresets.contains { $0.id == selectedAction?.id }
        return Menu {
            Section("More actions") {
                ForEach(Array(additionalActions.enumerated()), id: \.element.id) { index, action in
                    Button {
                        selectAction(SelectedAction(id: action.id, systemPrompt: action.systemPrompt, label: action.label))
                    } label: {
                        Label(action.label, systemImage: action.systemImage)
                    }
                    .keyboardShortcut(shortcutKey(index + directActions.count), modifiers: .command)
                }
            }
            if !settings.customPresets.isEmpty {
                Section("Your actions") {
                    ForEach(settings.customPresets) { preset in
                        Button {
                            selectAction(SelectedAction(id: preset.id,
                                                        systemPrompt: RewriteAction.customSystemPrompt(preset.instruction),
                                                        label: preset.label))
                        } label: {
                            Label(preset.label, systemImage: "star")
                        }
                    }
                }
            }
            Divider()
            Button {
                toggleCustom()
            } label: {
                Label("Custom instruction…", systemImage: "wand.and.rays")
            }
        } label: {
            actionMenuLabel(selected: moreSelected)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .disabled(isLoading)
        .opacity(isLoading ? 0.6 : 1)
        .fixedSize()
    }

    private func actionMenuLabel(selected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.3").font(.system(size: 11))
            Text("Actions").font(.system(size: 12.5))
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(selected ? Theme.accentInk : Theme.textPrimary)
        .padding(.horizontal, 13).padding(.vertical, 8)
        .background {
            if selected {
                Capsule().fill(Theme.accent)
            } else {
                Capsule().fill(.clear).adaptiveGlass(Capsule(), interactive: true)
            }
        }
        .contentShape(Capsule())
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
                if selected {
                    Capsule().fill(Theme.accent)
                } else {
                    Capsule().fill(.clear).adaptiveGlass(Capsule(), interactive: true)
                }
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
        GlassGroup {
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
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial)
            .shadow(color: Color.black.opacity(0.18), radius: 5, y: 1))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.accent.opacity(0.4), lineWidth: 1))
    }

    /// Growing pill input (1→~4 lines, then scrolls) with the send button inside.
    private var composerField: some View {
        HStack(alignment: .bottom, spacing: 6) {
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
        .background(RoundedRectangle(cornerRadius: 21, style: .continuous).fill(.regularMaterial)
            .shadow(color: Color.black.opacity(0.20), radius: 6, y: 2))
        .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(composerBorder, lineWidth: 1))
        // Enter sends; Shift+Enter inserts a newline. A window-local key monitor
        // (not SwiftUI's .onKeyPress, which leaks Return inside an NSPopover and
        // dismisses it) consumes Return before the field/popover can act on it.
        .background(SubmitKeyMonitor(onSubmit: { if !isLoading { sendDraft() } }))
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
        return thread.isEmpty ? "Rewrite or ask…" : "Add text or a reply…"
    }

    // MARK: - History panel

    private var historyPanel: some View {
        let items = settings.history
        return Group {
            if items.isEmpty {
                Text("No rewrites yet.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(items) { historyRow($0) }
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
                Text("Recent rewrites")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .glassFloat(Capsule())
                Spacer(minLength: 6)
                if !settings.history.isEmpty {
                    Button { settings.history = [] } label: {
                        Text("Clear")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .glassFloat(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
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
            .glassFloat(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func openHistory(_ item: HistoryItem) {
        settings.mode = .rewrite
        workspaceTab = .rewrite
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
        // Smart plain send (no explicit action): one decide-and-act pass that
        // either lightly improves text or fulfills a writing request.
        if selectedAction == nil && settings.smartIntent {
            addUserTurn(t)
            run(systemPrompt: "", label: "Improve", smart: true)
            return
        }
        // No explicit action picked → apply a light, safe improvement instead
        // of sending raw text that never gets rewritten.
        let sel = selectedAction ?? {
            let d = RewriteMode.rewrite.defaultAction
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
        let runMode = RewriteMode.rewrite
        currentTask?.cancel()
        isLoading = true

        // Smart uses its own single prompt and never wraps (it may legitimately
        // fulfill a request); the label is provisional until the tag resolves.
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
        tv.textColor = NSColor(Theme.textPrimary)
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
        context.coordinator.install()
        return NSView()
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
        private var monitor: Any?

        init(onSubmit: @escaping () -> Void) { self.onSubmit = onSubmit }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                // Return (36) / keypad Enter (76) / Space (49) while the composer is
                // focused. Inside the docked NSPopover these otherwise leak past the
                // field and dismiss the popover, so we act on them here (this local
                // monitor runs before window dispatch) and CONSUME them.
                guard event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49,
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
        .init(icon: "macwindow", title: "A full app window",
              blurb: "Open Rewrite as a resizable app from the Dock or Launchpad, with a conversations sidebar — your chats are saved and you pick up right where you left off."),
        .init(icon: "sparkles", title: "Smart in Prompt mode too",
              blurb: "In Prompt mode, Smart now decides for you: it sharpens a rough prompt, or — if you actually pasted something to write — just does it, instead of getting stuck."),
        .init(icon: "sidebar.left", title: "Chats, kept tidy",
              blurb: "Writing and Prompt keep separate threads, each in its own list, so your conversations never get tangled."),
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
