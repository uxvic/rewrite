import Foundation
import Combine

/// A saved, named conversation for the windowed (ChatGPT-style) app: the full
/// turn list plus the Rewrite flow it belongs to. Persisted as JSON. The menu-bar
/// popover keeps its own transient thread; this is the durable, multi-chat store.
struct Conversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var mode: RewriteMode
    var turns: [ChatTurn]
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String = "New chat", mode: RewriteMode = .rewrite,
         turns: [ChatTurn] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.mode = mode.canonical
        self.turns = turns
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// A title derived from the first user turn, used until the user renames it.
    static func derivedTitle(from turns: [ChatTurn]) -> String {
        guard let first = turns.first(where: { $0.role == .user && !$0.text.isEmpty })?.text
            .trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty else { return "New chat" }
        let oneLine = first.replacingOccurrences(of: "\n", with: " ")
        return oneLine.count > 40 ? String(oneLine.prefix(40)) + "…" : oneLine
    }
}

/// Loads/saves conversations and exposes them to the sidebar (most-recent first).
/// Backed by a single JSON file in Application Support/Rewrite.
final class ConversationStore: ObservableObject {
    /// One store behind BOTH the menu-bar popover and the app window, so a chat
    /// started in either surface shows up in the other (live while both are open,
    /// since they observe the same @Published list).
    static let shared = ConversationStore()

    @Published private(set) var conversations: [Conversation] = []

    private let fileURL: URL

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rewrite", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("conversations.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Conversation].self, from: data)
        else { return }
        var migrated = false
        conversations = decoded.map { conversation in
            var canonical = conversation
            let mode = canonical.mode.canonical
            if canonical.mode != mode {
                canonical.mode = mode
                migrated = true
            }
            return canonical
        }
        .sorted { $0.updatedAt > $1.updatedAt }
        if migrated { persist() }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Creates a new empty conversation at the top and returns it.
    @discardableResult
    func create(mode: RewriteMode = .rewrite) -> Conversation {
        let convo = Conversation(mode: mode.canonical)
        conversations.insert(convo, at: 0)
        persist()
        return convo
    }

    /// Inserts or replaces a conversation, re-titling from its first message while
    /// still "New chat", and bumps it to the top by recency.
    func save(_ conversation: Conversation) {
        var c = conversation
        c.mode = c.mode.canonical
        c.updatedAt = Date()
        if c.title == "New chat" { c.title = Conversation.derivedTitle(from: c.turns) }
        if let i = conversations.firstIndex(where: { $0.id == c.id }) {
            conversations[i] = c
        } else {
            conversations.insert(c, at: 0)
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        persist()
    }

    func rename(_ id: UUID, to title: String) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        conversations[i].title = trimmed.isEmpty ? "Untitled" : trimmed
        persist()
    }
}
