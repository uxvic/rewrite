import SwiftUI

/// The standalone, ChatGPT-style window: a conversations sidebar + a resizable
/// chat pane. Reuses the model/provider layer and the popover's native composer;
/// persists named chats via ConversationStore.
struct MainWindowView: View {
    @StateObject private var store: ConversationStore
    @StateObject private var engine: ChatEngine
    @State private var selection: UUID?
    @State private var showSettings = false

    init() {
        let store = ConversationStore.shared
        let initial = store.conversations.first ?? store.create()
        let engine = ChatEngine(initial)
        engine.onPersist = { store.save($0) }
        _store = StateObject(wrappedValue: store)
        _engine = StateObject(wrappedValue: engine)
        _selection = State(initialValue: initial.id)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            chat
        }
        .frame(minWidth: 760, minHeight: 500)
        .onChange(of: selection) { _, id in
            guard let id, id != engine.conversation.id,
                  let c = store.conversations.first(where: { $0.id == id }) else { return }
            engine.open(c)
        }
        .sheet(isPresented: $showSettings) {
            ZStack(alignment: .topTrailing) {
                SettingsView().ambientBackground()
                Button { showSettings = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17)).foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain).padding(12).keyboardShortcut(.cancelAction)
            }
            .frame(width: 480, height: 640)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            Text("Rewrite")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 18)

            HStack {
                Text("Chats").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button(action: newChat) {
                    Image(systemName: "square.and.pencil").font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accent).help("New chat")
            }
            .padding(.horizontal, 14).padding(.bottom, 8)

            List(selection: $selection) {
                ForEach(store.conversations) { c in
                    Text(c.title.isEmpty ? "New chat" : c.title)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textPrimary)
                        .tag(c.id)
                        .contextMenu {
                            Button("Delete", role: .destructive) { delete(c.id) }
                        }
                }
            }
            .listStyle(.sidebar)

            // Settings pinned at the bottom of the side nav.
            Divider().opacity(0.35)
            Button { showSettings = true } label: {
                HStack(spacing: 9) {
                    Image(systemName: "gearshape").font(.system(size: 13))
                    Text("Settings").font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .frame(minWidth: 210)
    }

    // MARK: - Chat pane

    private var chat: some View {
        VStack(spacing: 0) {
            messages
            Divider().opacity(0.4)
            composer
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if engine.turns.isEmpty {
                        Text("Start a conversation — type below and press Return.")
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 60)
                    }
                    ForEach(engine.turns) { turn in
                        turnRow(turn).id(turn.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(20)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: engine.turns.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private func turnRow(_ turn: ChatTurn) -> some View {
        if turn.role == .user {
            HStack {
                Spacer(minLength: 60)
                Text(turn.text)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.fillTranslucent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if !turn.actionLabel.isEmpty {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6)
                        Text(turn.actionLabel).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                    }
                }
                Text(turn.text.isEmpty && turn.isStreaming ? "…" : turn.text)
                    .foregroundStyle(turn.isError ? Theme.ledFail : Theme.textPrimary)
                    .textSelection(.enabled)
                if !turn.isStreaming && !turn.text.isEmpty {
                    assistantActions(turn)
                }
            }
        }
    }

    private func assistantActions(_ turn: ChatTurn) -> some View {
        HStack(spacing: 8) {
            Button("Copy") { ChatEngine.setClipboard(turn.text) }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            Menu("Retry") {
                Button("Try again") { engine.retryAgain(turn) }
                Divider()
                ForEach(RewriteMode.rewrite.actions) { a in
                    Button(a.label) { engine.retryAs(a, turn) }
                }
            }
            .menuStyle(.button).buttonStyle(.plain).fixedSize()
            .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 2)
        .disabled(engine.isLoading)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if engine.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(engine.mode.inputPlaceholder)
                            .foregroundStyle(Theme.textSecondary).allowsHitTesting(false).padding(.leading, 4)
                    }
                    ComposerTextView(text: $engine.draft, maxLines: 8)
                }
                .padding(10)
                .glassFloat(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if engine.isLoading {
                    IconButton(systemName: "stop.fill", help: "Stop") { engine.stop() }
                } else {
                    IconButton(systemName: "arrow.up", prominent: true, help: "Send") { if engine.canSend { engine.send() } }
                        .opacity(engine.canSend ? 1 : 0.4)
                }
            }
            .background(SubmitKeyMonitor(onSubmit: { if !engine.isLoading { engine.send() } }))

            actionChips
        }
        .frame(maxWidth: 760)            // centered column, not full window width
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var actionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                chip("✦ Smart", active: engine.smartActive) { engine.toggleSmart() }
                ForEach(engine.actions) { a in
                    chip(a.label, active: engine.selectedActionID == a.id) { engine.selectAction(a.id) }
                }
            }
        }
    }

    private func chip(_ label: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(active ? Theme.accentInk : Theme.textPrimary)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(active ? Theme.accent : Theme.fillTranslucent.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func newChat() {
        let c = store.create()
        engine.open(c)
        selection = c.id
    }

    private func delete(_ id: UUID) {
        store.delete(id)
        if engine.conversation.id == id {
            let next = store.conversations.first ?? store.create()
            engine.open(next)
            selection = next.id
        }
    }
}
