import Foundation
import Combine
import ServiceManagement

enum LLMProvider: String, CaseIterable, Identifiable {
    case appleOnDevice
    case hosted
    case ollama
    case anthropic
    case claudeCode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleOnDevice: return "Built-in AI (on-device, free)"
        case .hosted:        return "Free models (newsletter)"
        case .ollama:        return "Open-source local (Ollama)"
        case .anthropic:     return "Claude (paid API)"
        case .claudeCode:    return "Claude Code (Max subscription)"
        }
    }

    /// True for engines that need no key/account/sign-in.
    var isZeroSetup: Bool { self == .appleOnDevice }
}

/// One past rewrite, kept for the history panel.
struct HistoryItem: Codable, Identifiable {
    let id: String
    let actionLabel: String
    let input: String
    let output: String
    var mode: RewriteMode = .rewrite

    private enum CodingKeys: String, CodingKey { case id, actionLabel, input, output, mode }

    init(id: String, actionLabel: String, input: String, output: String, mode: RewriteMode = .rewrite) {
        self.id = id; self.actionLabel = actionLabel; self.input = input; self.output = output; self.mode = mode
    }

    // Decode older saved items that predate `mode` by defaulting to .writing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        actionLabel = try c.decode(String.self, forKey: .actionLabel)
        input = try c.decode(String.self, forKey: .input)
        output = try c.decode(String.self, forKey: .output)
        mode = (try c.decodeIfPresent(RewriteMode.self, forKey: .mode))?.canonical ?? .rewrite
    }
}

/// A user-defined preset button (label + instruction).
struct CustomPreset: Codable, Identifiable {
    let id: String
    var label: String
    var instruction: String
}

extension Notification.Name {
    static let hotKeysChanged = Notification.Name("RewriteHotKeysChanged")
}

/// Registers/unregisters the app as a macOS login item.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Rewrite: login item update failed: \(error.localizedDescription)")
        }
    }
}

/// App-wide, persisted settings. The API key lives in the Keychain; everything
/// else in UserDefaults. Shared singleton so all views stay in sync.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var provider: LLMProvider {
        didSet { defaults.set(provider.rawValue, forKey: "provider") }
    }
    @Published var anthropicModel: String {
        didSet { defaults.set(anthropicModel, forKey: "anthropicModel") }
    }
    @Published var ollamaModel: String {
        didSet { defaults.set(ollamaModel, forKey: "ollamaModel") }
    }
    @Published var ollamaHost: String {
        didSet { defaults.set(ollamaHost, forKey: "ollamaHost") }
    }
    @Published var claudeCodePath: String {
        didSet { defaults.set(claudeCodePath, forKey: "claudeCodePath") }
    }
    @Published var apiKey: String {
        didSet { apiKey.isEmpty ? KeychainStore.delete() : KeychainStore.save(apiKey) }
    }

    // Hosted "free models" gateway
    @Published var hostedToken: String {
        didSet { hostedToken.isEmpty ? KeychainStore.deleteHostedToken() : KeychainStore.saveHostedToken(hostedToken) }
    }
    @Published var hostedEmail: String {
        didSet { defaults.set(hostedEmail, forKey: "hostedEmail") }
    }
    @Published var gatewayBaseURL: String {
        didSet { defaults.set(gatewayBaseURL, forKey: "gatewayBaseURL") }
    }
    /// The app version whose "What's new" card the user has already seen.
    @Published var lastSeenWhatsNewVersion: String {
        didSet { defaults.set(lastSeenWhatsNewVersion, forKey: "lastSeenWhatsNewVersion") }
    }
    var isSignedInToHosted: Bool { !hostedToken.isEmpty }

    // Hotkeys
    @Published var popoverHotKeyID: String {
        didSet {
            defaults.set(popoverHotKeyID, forKey: "popoverHotKeyID")
            NotificationCenter.default.post(name: .hotKeysChanged, object: nil)
        }
    }
    @Published var inPlaceHotKeyID: String {
        didSet {
            defaults.set(inPlaceHotKeyID, forKey: "inPlaceHotKeyID")
            NotificationCenter.default.post(name: .hotKeysChanged, object: nil)
        }
    }

    /// Action used by the "rewrite selection in place" hotkey.
    @Published var defaultInPlaceAction: RewriteAction {
        didSet { defaults.set(defaultInPlaceAction.rawValue, forKey: "defaultInPlaceAction") }
    }

    @Published var launchAtLogin: Bool {
        didSet { LoginItem.set(launchAtLogin) }
    }

    @Published var recordingSounds: Bool {
        didSet { defaults.set(recordingSounds, forKey: "recordingSounds") }
    }
    @Published var mode: RewriteMode {
        didSet { defaults.set(mode.rawValue, forKey: "mode") }
    }
    @Published var autoFillClipboard: Bool {
        didSet { defaults.set(autoFillClipboard, forKey: "autoFillClipboard") }
    }
    /// Clipboard History starts enabled, but remains an explicit local preference
    /// so a user can stop all subsequent capture without losing other settings.
    @Published var clipboardHistoryEnabled: Bool {
        didSet { defaults.set(clipboardHistoryEnabled, forKey: "clipboardHistoryEnabled") }
    }
    @Published var autoCopyResult: Bool {
        didSet { defaults.set(autoCopyResult, forKey: "autoCopyResult") }
    }
    /// Smart send: on a plain send (no style picked) in Writing, classify whether
    /// the input is text to polish or a request to fulfill, and act accordingly.
    @Published var smartIntent: Bool {
        didSet { defaults.set(smartIntent, forKey: "smartIntent") }
    }

    @Published var history: [HistoryItem] {
        didSet { persist(history, key: "history") }
    }
    @Published var customPresets: [CustomPreset] {
        didSet { persist(customPresets, key: "customPresets") }
    }

    static let anthropicModels = ["claude-haiku-4-5", "claude-sonnet-4-6", "claude-opus-4-8"]

    private init() {
        // First run: default to the best zero-setup engine available.
        if let saved = defaults.string(forKey: "provider").flatMap(LLMProvider.init(rawValue:)) {
            provider = saved
        } else {
            provider = AppleOnDeviceProvider.isAvailable ? .appleOnDevice : .hosted
        }
        anthropicModel = defaults.string(forKey: "anthropicModel") ?? "claude-haiku-4-5"
        ollamaModel = defaults.string(forKey: "ollamaModel") ?? "llama3.2"
        ollamaHost = defaults.string(forKey: "ollamaHost") ?? "http://localhost:11434"
        claudeCodePath = defaults.string(forKey: "claudeCodePath") ?? ""
        apiKey = KeychainStore.load() ?? ""
        hostedToken = KeychainStore.loadHostedToken() ?? ""
        hostedEmail = defaults.string(forKey: "hostedEmail") ?? ""
        gatewayBaseURL = defaults.string(forKey: "gatewayBaseURL") ?? GatewayConfig.defaultBaseURL
        lastSeenWhatsNewVersion = defaults.string(forKey: "lastSeenWhatsNewVersion") ?? ""
        popoverHotKeyID = defaults.string(forKey: "popoverHotKeyID") ?? "optSpace"
        inPlaceHotKeyID = defaults.string(forKey: "inPlaceHotKeyID") ?? "optShiftSpace"
        defaultInPlaceAction = defaults.string(forKey: "defaultInPlaceAction")
            .flatMap(RewriteAction.init(rawValue:)) ?? .paraphrase
        launchAtLogin = LoginItem.isEnabled
        recordingSounds = defaults.object(forKey: "recordingSounds") == nil ? true : defaults.bool(forKey: "recordingSounds")
        mode = defaults.string(forKey: "mode").flatMap(RewriteMode.init(rawValue:))?.canonical ?? .rewrite
        autoFillClipboard = defaults.object(forKey: "autoFillClipboard") == nil ? true : defaults.bool(forKey: "autoFillClipboard")
        clipboardHistoryEnabled = defaults.object(forKey: "clipboardHistoryEnabled") == nil
            ? true : defaults.bool(forKey: "clipboardHistoryEnabled")
        autoCopyResult = defaults.bool(forKey: "autoCopyResult")
        smartIntent = defaults.object(forKey: "smartIntent") == nil ? true : defaults.bool(forKey: "smartIntent")
        history = Self.read([HistoryItem].self, key: "history") ?? []
        customPresets = Self.read([CustomPreset].self, key: "customPresets") ?? []
    }

    func makeProvider() -> RewriteProvider {
        switch provider {
        case .appleOnDevice: return AppleOnDeviceProvider()
        case .hosted:        return HostedProvider(baseURL: gatewayBaseURL, token: hostedToken)
        case .anthropic:     return AnthropicProvider(apiKey: apiKey, model: anthropicModel)
        case .claudeCode:    return ClaudeCodeProvider(configuredPath: claudeCodePath)
        case .ollama:        return OllamaProvider(host: ollamaHost, model: ollamaModel)
        }
    }

    func addHistory(actionLabel: String, input: String, output: String, mode: RewriteMode) {
        let item = HistoryItem(id: UUID().uuidString, actionLabel: actionLabel, input: input, output: output, mode: mode)
        history.insert(item, at: 0)
        if history.count > 20 { history = Array(history.prefix(20)) }
    }

    func addCustomPreset(label: String, instruction: String) {
        customPresets.append(CustomPreset(id: UUID().uuidString, label: label, instruction: instruction))
    }

    func removeCustomPreset(_ preset: CustomPreset) {
        customPresets.removeAll { $0.id == preset.id }
    }

    // MARK: - JSON persistence helpers

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
    private static func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
