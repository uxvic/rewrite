import SwiftUI
import AppKit

/// Drives one conversation in the windowed (ChatGPT-style) app: the send → run →
/// stream pipeline, Smart decide-and-act, and retry — as a reusable ObservableObject
/// bound to a persisted `Conversation`. Adapted from PopoverView's inline logic; the
/// menu-bar popover keeps its own copy, so this change can't destabilize it.
@MainActor
final class ChatEngine: ObservableObject {
    @Published var conversation: Conversation
    @Published var draft: String = ""
    @Published var isLoading = false
    /// nil = Smart (Writing) or the mode's default; otherwise an explicit action id.
    @Published var selectedActionID: String?

    /// Invoked after any change worth persisting (the window saves to the store).
    var onPersist: ((Conversation) -> Void)?

    private var currentTask: Task<Void, Never>?
    private let settings = AppSettings.shared

    init(_ conversation: Conversation) { self.conversation = conversation }

    // MARK: - Derived

    var turns: [ChatTurn] { conversation.turns }
    var mode: RewriteMode { conversation.mode }
    var actions: [PresetAction] { conversation.mode.actions }
    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }
    var smartActive: Bool {
        settings.smartIntent && selectedActionID == nil && conversation.mode == .writing
    }

    private var latestUserText: String {
        for t in conversation.turns.reversed() where t.role == .user {
            return t.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    // MARK: - Conversation lifecycle

    /// Switch the engine to another conversation (cancels any in-flight run).
    func open(_ c: Conversation) {
        currentTask?.cancel()
        isLoading = false
        conversation = c
        draft = ""
        selectedActionID = nil
    }

    func setMode(_ m: RewriteMode) {
        guard m != conversation.mode else { return }
        conversation.mode = m
        selectedActionID = nil
        persist()
    }

    func selectAction(_ id: String) {
        selectedActionID = (selectedActionID == id) ? nil : id
    }

    func toggleSmart() {
        let wasActive = smartActive
        selectedActionID = nil
        settings.smartIntent = !wasActive
        objectWillChange.send()
    }

    // MARK: - Send / run

    func send() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }

        // Smart plain send (Writing, no explicit action) → one decide-and-act pass.
        if selectedActionID == nil && conversation.mode == .writing && settings.smartIntent {
            addUserTurn(t)
            run(systemPrompt: "", label: "Improve", smart: true)
            return
        }
        let action = resolveAction()
        addUserTurn(t)
        run(systemPrompt: action.systemPrompt, label: action.label)
    }

    func stop() { currentTask?.cancel() }

    func retryAgain(_ turn: ChatTurn) {
        run(systemPrompt: turn.systemPrompt, label: turn.actionLabel, variation: true,
            source: turn.sourceText, wrap: !turn.fulfillsRequest, smart: turn.isSmart)
    }

    func retryAs(_ action: PresetAction, _ turn: ChatTurn) {
        run(systemPrompt: action.systemPrompt, label: action.label, source: turn.sourceText)
    }

    private func resolveAction() -> PresetAction {
        if let id = selectedActionID, let a = conversation.mode.actions.first(where: { $0.id == id }) {
            return a
        }
        return conversation.mode.defaultAction
    }

    private func addUserTurn(_ t: String) {
        conversation.turns.append(ChatTurn(role: .user, text: t))
        draft = ""
        persist()
    }

    private func run(systemPrompt: String, label: String, variation: Bool = false,
                     source: String? = nil, wrap: Bool = true, smart: Bool = false) {
        let src = (source ?? latestUserText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else { return }
        currentTask?.cancel()
        isLoading = true

        let prompt = smart ? RewriteAction.smartSystemPrompt : systemPrompt
        let turn = ChatTurn(role: .assistant, text: "", actionLabel: label,
                            systemPrompt: prompt, isStreaming: true, sourceText: src,
                            fulfillsRequest: !wrap && !smart, isSmart: smart)
        let id = turn.id
        conversation.turns.append(turn)

        let provider = settings.makeProvider()
        var payload: String
        if smart { payload = smartContextPayload() ?? src }
        else { payload = wrap ? RewriteAction.wrap(src) : src }
        if variation { payload += "\n\n(Give a noticeably different alternative version.)" }
        let runMode = conversation.mode

        currentTask = Task {
            await streamBody(turnID: id, src: src, payload: payload, systemPrompt: prompt,
                             label: label, runMode: runMode, provider: provider, parseSmartTag: smart)
        }
    }

    /// Conversation transcript so a Smart follow-up refines rather than restarts.
    private func smartContextPayload() -> String? {
        let turns = conversation.turns.filter {
            ($0.role == .user || $0.role == .assistant)
            && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard turns.count > 1 else { return nil }
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

    private func streamBody(turnID id: UUID, src: String, payload: String,
                            systemPrompt: String, label: String, runMode: RewriteMode,
                            provider: any RewriteProvider, parseSmartTag: Bool) async {
        do {
            let raw = try await provider.stream(text: payload, systemPrompt: systemPrompt) { piece in
                Task { @MainActor in
                    if parseSmartTag {
                        self.mutateTurn(id) {
                            $0.rawText += piece
                            let p = RewriteAction.parseSmart($0.rawText)
                            if let l = p.label { $0.actionLabel = l; $0.fulfillsRequest = (l == "Request") }
                            $0.text = p.body
                        }
                    } else {
                        self.mutateTurn(id) { $0.text += piece }
                    }
                }
            }
            let parsed: (label: String?, body: String) = parseSmartTag
                ? RewriteAction.parseSmart(raw)
                : (label: nil, body: RewriteAction.clean(raw))
            let result = parsed.body
            let finalLabel = parsed.label ?? label
            mutateTurn(id) {
                $0.text = result; $0.isStreaming = false
                if parseSmartTag {
                    $0.actionLabel = finalLabel
                    $0.fulfillsRequest = (parsed.label == "Request")
                }
            }
            isLoading = false
            settings.addHistory(actionLabel: finalLabel, input: src, output: result, mode: runMode)
            if settings.autoCopyResult { Self.setClipboard(result) }
            persist()
        } catch {
            isLoading = false
            if Task.isCancelled {
                conversation.turns.removeAll { $0.id == id && $0.text.isEmpty }
                mutateTurn(id) { $0.isStreaming = false }
            } else {
                mutateTurn(id) {
                    $0.text = error.localizedDescription
                    $0.isStreaming = false
                    $0.isError = true
                }
            }
            persist()
        }
    }

    private func mutateTurn(_ id: UUID, _ change: (inout ChatTurn) -> Void) {
        if let i = conversation.turns.firstIndex(where: { $0.id == id }) { change(&conversation.turns[i]) }
    }

    private func persist() { onPersist?(conversation) }

    static func setClipboard(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
