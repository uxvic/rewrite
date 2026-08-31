import AppKit
import Combine

/// One local text copy. Clipboard history deliberately stores no source-app
/// metadata: it would add sensitive behavioural data without helping the core
/// "bring this text back into Rewrite" job.
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// Watches the general pasteboard while Rewrite is running and keeps a local,
/// bounded history of ordinary text copies. Clipboard items never reach a model
/// provider unless the user explicitly sends one through the Rewrite composer.
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    @Published private(set) var items: [ClipboardItem] = []

    private let fileURL: URL
    private var timer: Timer?
    private var lastChangeCount: Int
    private let maximumItems = 100
    private let maximumTextLength = 10_000

    /// These markers are conventionally used by pasteboard clients for content
    /// that should not become normal history, such as concealed secrets and
    /// transient drag-and-drop payloads.
    private static let excludedTypes: Set<NSPasteboard.PasteboardType> = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    ]

    private init() {
        #if DEBUG
        let directoryName = "Rewrite Debug"
        #else
        let directoryName = "Rewrite"
        #endif
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("clipboard-history.json")
        items = Self.loadItems(from: fileURL)
        lastChangeCount = NSPasteboard.general.changeCount
    }

    /// Capture begins automatically when Rewrite launches. The initial change
    /// count is only a baseline, so a copy made before launch is not added later.
    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
        timer.tolerance = 0.12
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func clear() {
        items = []
        persist()
    }

    private func pollPasteboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        // While disabled, still advance the baseline so re-enabling does not
        // capture content copied while history was turned off.
        guard AppSettings.shared.clipboardHistoryEnabled else { return }
        guard let types = pasteboard.types,
              Self.excludedTypes.isDisjoint(with: Set(types)),
              let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= maximumTextLength
        else { return }

        // Re-copying an older item moves it to the top rather than making a
        // duplicate. The exact content, including line breaks, is preserved.
        items.removeAll { $0.text == text }
        items.insert(ClipboardItem(text: text), at: 0)
        if items.count > maximumItems { items = Array(items.prefix(maximumItems)) }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func loadItems(from url: URL) -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode([ClipboardItem].self, from: data)
        else { return [] }
        return stored.sorted { $0.createdAt > $1.createdAt }
    }
}
