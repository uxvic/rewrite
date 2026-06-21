import SwiftUI
import AppKit

/// One message in the rewrite conversation. User turns hold the source text;
/// assistant turns hold a rewrite (streamed in) plus the action that produced it.
struct ChatTurn: Identifiable, Equatable {
    enum Role { case user, assistant }
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

struct PopoverView: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var speech = SpeechManager()

    @State private var thread: [ChatTurn] = []
    @State private var draft = ""
    @State private var composerMode: ComposerMode = .text
    @State private var isLoading = false
    @State private var currentTask: Task<Void, Never>?
    @State private var copiedTurnID: UUID?
    @State private var composerFocused = false
    @State private var voiceMode = false
    @State private var fromClipboard = false
    @State private var lastClipboardCount = -1

    private enum Panel { case main, settings, history }
    @State private var panel: Panel = .main

    var body: some View {
        Group {
            if voiceMode {
                VoiceOverlayView(speech: speech, onDone: finishVoice, onCancel: cancelVoice)
            } else {
                VStack(spacing: 0) {
                    specBar
                    HairlineDivider()
                    if panel == .main {
                        modeSwitcher
                        HairlineDivider()
                    }
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
        .background(Theme.bg)
        .onAppear { autoFillFromClipboard() }
    }

    // MARK: - Spec bar

    private var specBar: some View {
        HStack(spacing: 8) {
            Text("REWRITE").font(.display(16)).tracking(2).foregroundStyle(Theme.textPrimary)
            Text("v\(appVersion)").font(.mono(9)).tracking(1).foregroundStyle(Theme.textSecondary)
            Spacer()
            LEDDot(color: Theme.accent)
            Text(providerShortName.uppercased()).font(.mono(10)).tracking(2).foregroundStyle(Theme.textSecondary)
            if panel == .main {
                Button { newChat() } label: {
                    Image(systemName: "square.and.pencil").foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.borderless).help("New chat")
                .disabled(thread.isEmpty && draft.isEmpty)
            }
            Button { panel = (panel == .history) ? .main : .history } label: {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.textSecondary)
            }.buttonStyle(.borderless).help("History")
            Button { panel = (panel == .settings) ? .main : .settings } label: {
                Image(systemName: panel == .settings ? "chevron.left" : "gearshape").foregroundStyle(Theme.textSecondary)
            }.buttonStyle(.borderless).help("Settings")
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    private var providerShortName: String {
        switch settings.provider {
        case .appleOnDevice: return "On-device"
        case .hosted:        return "Free"
        case .anthropic:     return "Claude"
        case .claudeCode:    return "Claude Code"
        case .ollama:        return "Ollama"
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Mode switcher

    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(RewriteMode.allCases) { m in
                let active = settings.mode == m
                Button { settings.mode = m } label: {
                    Text(m.title)
                        .font(.monoLabel(11)).tracking(2)
                        .foregroundStyle(active ? Theme.accentInk : Theme.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(active ? Theme.accent : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: Metric.radius).stroke(Theme.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Metric.radius))
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - Chat panel

    private var chatPanel: some View {
        VStack(spacing: 0) {
            threadView
            composer
        }
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
                    if canAct { chipsRow }
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
        if turn.role == .user { userBubble(turn) } else { assistantTurn(turn) }
    }

    private func userBubble(_ turn: ChatTurn) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            if turn.fromClipboard {
                Text("FROM CLIPBOARD").font(.monoLabel(9)).tracking(1).foregroundStyle(Theme.textSecondary)
            }
            Text(turn.text)
                .font(.system(size: 13.5)).foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 13).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 36)
    }

    private func assistantTurn(_ turn: ChatTurn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(turn.isError ? Theme.ledFail : Theme.accent).frame(width: 6, height: 6)
                Text(turn.actionLabel.uppercased()).font(.monoLabel(9)).tracking(1.5)
                    .foregroundStyle(turn.isError ? Theme.ledFail : Theme.accent)
                    .lineLimit(1)
            }
            bodyText(turn)
                .font(.system(size: 13.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(.horizontal, 13).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(turn.isStreaming ? Theme.accent : Theme.hairline, lineWidth: 1))
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
        let shown = (turn.text.isEmpty && turn.isStreaming) ? "…" : turn.text
        let base = Text(shown).foregroundColor(Theme.textPrimary)
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
                Text(label).font(.monoLabel(10)).tracking(0.5)
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action chips

    private var chipsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(thread.contains { $0.role == .assistant } ? "TRY ANOTHER" : "REWRITE AS")
                .font(.monoLabel(9)).tracking(1.5).foregroundStyle(Theme.textSecondary)
            FlowLayout(spacing: 7) {
                ForEach(Array(settings.mode.actions.enumerated()), id: \.element.id) { idx, action in
                    actionChip(icon: action.systemImage, label: action.label) {
                        run(systemPrompt: action.systemPrompt, label: action.label)
                    }
                    .keyboardShortcut(shortcutKey(idx), modifiers: .command)
                }
                ForEach(settings.customPresets) { preset in
                    actionChip(icon: "star", label: preset.label) {
                        run(systemPrompt: RewriteAction.customSystemPrompt(preset.instruction), label: preset.label)
                    }
                }
                actionChip(icon: "wand.and.rays", label: "Custom…",
                           prominent: composerMode == .instruction) {
                    composerMode = .instruction
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionChip(icon: String, label: String, prominent: Bool = false,
                            _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11))
                    .foregroundStyle(prominent ? Theme.accentInk : Theme.textSecondary)
                Text(label).font(.system(size: 12.5))
                    .foregroundStyle(prominent ? Theme.accentInk : Theme.textPrimary)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(prominent ? Theme.accent : Theme.panel))
            .overlay(Capsule().stroke(prominent ? Theme.accent : Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .opacity(isLoading ? 0.5 : 1)
    }

    private func shortcutKey(_ index: Int) -> KeyEquivalent {
        guard index < 9 else { return KeyEquivalent("0") }
        return KeyEquivalent(Character("\(index + 1)"))
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 0) {
            HairlineDivider()
            VStack(spacing: 7) {
                HStack(alignment: .bottom, spacing: 8) {
                    composerField
                    micButton
                    sendButton
                }
                composerHint
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
    }

    private var composerField: some View {
        ZStack(alignment: .topLeading) {
            if draft.isEmpty {
                Text(composerPlaceholder)
                    .font(.system(size: 13.5)).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 11).allowsHitTesting(false)
            }
            AutoScrollTextEditor(text: $draft, isFocused: $composerFocused,
                                 font: .systemFont(ofSize: 13.5), textColor: Theme.nsTextPrimary,
                                 autoScroll: false, autoFocus: true)
                .frame(height: 44)
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
            composerMode == .instruction ? Theme.accent : (composerFocused ? Theme.accent : Theme.hairline),
            lineWidth: 1))
    }

    private var composerPlaceholder: String {
        if composerMode == .instruction { return "Describe how to rewrite…  (⌘↩)" }
        return thread.isEmpty ? settings.mode.inputPlaceholder : "Add text or a reply…"
    }

    private var micButton: some View {
        Button { enterVoiceMode() } label: {
            Image(systemName: "mic.fill").font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.surface))
                .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain).help("Dictate")
    }

    private var sendButton: some View {
        Button { isLoading ? currentTask?.cancel() : sendDraft() } label: {
            Image(systemName: isLoading ? "stop.fill" : "arrow.up")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accentInk)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.accent))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!isLoading && draftIsEmpty)
        .opacity(!isLoading && draftIsEmpty ? 0.5 : 1)
        .help(isLoading ? "Stop" : (composerMode == .instruction ? "Run instruction" : "Add to chat"))
    }

    private var composerHint: some View {
        HStack {
            if isLoading {
                Text("STREAMING…").font(.mono(9)).tracking(1).foregroundStyle(Theme.accent)
            } else if composerMode == .instruction {
                Text("CUSTOM INSTRUCTION").font(.mono(9)).tracking(1).foregroundStyle(Theme.accent)
            } else {
                Text("\(wordCount(draft)) WORDS").font(.mono(9)).tracking(1).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text(canAct ? "⌘1–\(min(settings.mode.actions.count, 9)) ACTIONS" : "⌘↩ SEND")
                .font(.mono(9)).tracking(1).foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - History panel

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "RECENT REWRITES")
                Spacer()
                if !settings.history.isEmpty {
                    Button { settings.history = [] } label: { Text("CLEAR") }
                        .buttonStyle(InstrumentButtonStyle()).controlSize(.mini)
                }
            }
            if settings.history.isEmpty {
                Text("Your recent rewrites will appear here.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(settings.history) { item in
                            Button { openHistory(item) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.actionLabel.uppercased())
                                        .font(.monoLabel(9)).tracking(1).foregroundStyle(Theme.accent)
                                    Text(item.output).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .module(Theme.panel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity)
    }

    private func openHistory(_ item: HistoryItem) {
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
    private var canAct: Bool { !latestUserText.isEmpty && !isLoading }
    private var draftIsEmpty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func wordCount(_ s: String) -> Int {
        s.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }

    // MARK: - Actions

    private func sendDraft() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if composerMode == .instruction {
            guard !latestUserText.isEmpty else { composerMode = .text; return }
            draft = ""; composerMode = .text
            run(systemPrompt: RewriteAction.customSystemPrompt(t), label: "Custom: \(t)")
        } else {
            thread.append(ChatTurn(role: .user, text: t, fromClipboard: fromClipboard))
            draft = ""; fromClipboard = false
        }
    }

    private func run(systemPrompt: String, label: String, variation: Bool = false, source: String? = nil) {
        let src = (source ?? latestUserText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else { return }
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
                    settings.addHistory(actionLabel: label, input: src, output: result)
                    if settings.autoCopyResult { setClipboard(result) }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    if Task.isCancelled {
                        thread.removeAll { $0.id == id && $0.text.isEmpty }
                        mutateTurn(id) { $0.isStreaming = false }
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

    private func newChat() {
        currentTask?.cancel()
        isLoading = false
        thread = []
        draft = ""
        composerMode = .text
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
        thread.append(ChatTurn(role: .user, text: captured))
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
            thread.append(ChatTurn(role: .user, text: s, fromClipboard: true))
        }
    }

    private func setClipboard(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

/// A simple wrapping layout (left-aligned rows) for the action chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        let width = maxWidth == .infinity ? x : maxWidth
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
