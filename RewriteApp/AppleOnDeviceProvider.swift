import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Uses Apple's built-in on-device model (Foundation Models, macOS 26+).
/// Zero setup: no key, no account, no download, fully private & offline.
/// Available on Apple-Silicon Macs with Apple Intelligence enabled.
struct AppleOnDeviceProvider: RewriteProvider {

    func stream(text: String,
                systemPrompt: String,
                onDelta: @Sendable @escaping (String) -> Void) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                throw RewriteError.badResponse(Self.unavailableMessage)
            }
            let session = LanguageModelSession(instructions: systemPrompt)
            let response = try await session.respond(to: text)
            let result = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else { throw RewriteError.empty }
            onDelta(result)
            return result
        } else {
            throw RewriteError.badResponse("The built-in AI requires macOS 26 or later. Choose another provider in Settings.")
        }
        #else
        throw RewriteError.badResponse("This build was compiled without Apple's on-device AI. Choose another provider in Settings.")
        #endif
    }

    func verify() async throws -> String {
        guard Self.isAvailable else { throw RewriteError.badResponse(Self.unavailableMessage) }
        return "Connected · on-device"
    }

    /// Whether the built-in model can be used right now (drives the default provider + UI).
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        return false
        #else
        return false
        #endif
    }

    static var unavailableMessage: String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "Available."
            case .unavailable(.deviceNotEligible):
                return "This Mac doesn't support the built-in AI (needs Apple Silicon). Choose another provider in Settings."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence (System Settings → Apple Intelligence & Siri) to use the built-in AI, or choose another provider."
            case .unavailable(.modelNotReady):
                return "The built-in AI is still downloading/preparing. Try again shortly, or choose another provider."
            case .unavailable:
                return "The built-in AI isn't available right now. Choose another provider in Settings."
            }
        }
        return "The built-in AI requires macOS 26 or later. Choose another provider in Settings."
        #else
        return "This build was compiled without Apple's on-device AI."
        #endif
    }
}
