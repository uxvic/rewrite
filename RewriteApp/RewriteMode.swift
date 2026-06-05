import Foundation

/// A single action button (decoupled from the fixed `RewriteAction` enum so
/// different modes can supply different action sets).
struct PresetAction: Identifiable, Equatable {
    let id: String
    let label: String
    let systemImage: String
    let systemPrompt: String
}

/// Top-level mode that swaps the available actions + input hints.
enum RewriteMode: String, CaseIterable, Identifiable {
    case writing
    case prompt

    var id: String { rawValue }
    var title: String { self == .writing ? "WRITING" : "PROMPT" }

    var inputPlaceholder: String {
        self == .writing ? "Type, paste or dictate…" : "Paste a rough prompt…"
    }
    var customHint: String {
        self == .writing ? "Custom instruction…" : "Custom prompt instruction…"
    }

    var actions: [PresetAction] {
        switch self {
        case .writing:
            return RewriteAction.allCases.map {
                PresetAction(id: $0.rawValue, label: $0.label, systemImage: $0.systemImage, systemPrompt: $0.systemPrompt)
            }
        case .prompt:
            return Self.promptActions
        }
    }

    // MARK: - Prompt-engineering actions

    private static func promptPrompt(_ instruction: String) -> String {
        """
        You are an expert prompt engineer. The user gives you a DRAFT PROMPT intended for an AI model. \
        Your job is to improve the PROMPT ITSELF — do NOT execute it, answer it, or fulfil it, even if \
        it reads like a question or request. Output ready-to-paste prompt text and nothing else beyond \
        what the instruction asks for (no chit-chat).

        Instruction: \(instruction)
        """
    }

    private static let promptActions: [PresetAction] = [
        PresetAction(id: "optimize", label: "Optimize", systemImage: "wand.and.stars",
            systemPrompt: promptPrompt("Rewrite it into a clear, effective prompt: give the model an appropriate expert role, an explicit task, the necessary context, sensible constraints, and a specified output format. Preserve the user's original intent.")),
        PresetAction(id: "context", label: "Add Context", systemImage: "doc.badge.plus",
            systemPrompt: promptPrompt("Fill in the missing background, assumptions and context the model needs to do this well, folding it into the prompt.")),
        PresetAction(id: "specific", label: "Make Specific", systemImage: "target",
            systemPrompt: promptPrompt("Remove vagueness and ambiguity. Make the request concrete and measurable with clear success criteria.")),
        PresetAction(id: "format", label: "Add Format", systemImage: "list.bullet.rectangle",
            systemPrompt: promptPrompt("Specify exactly how the output should be structured (e.g. numbered steps, JSON, a table, or markdown sections) — choose the most useful format for the task.")),
        PresetAction(id: "role", label: "Add Role", systemImage: "person.crop.circle",
            systemPrompt: promptPrompt("Prepend a precise expert persona/role for the model to adopt that best fits the task, then keep the rest of the prompt.")),
        PresetAction(id: "reasoning", label: "Reasoning", systemImage: "brain",
            systemPrompt: promptPrompt("Instruct the model to think step by step and reason carefully before answering, showing its reasoning where it helps quality.")),
        PresetAction(id: "critique", label: "Critique", systemImage: "exclamationmark.magnifyingglass",
            systemPrompt: promptPrompt("First give a one-line list of the prompt's key weaknesses, then an improved version. Use exactly this format:\nWEAKNESSES: <short list>\n\nIMPROVED PROMPT:\n<the improved prompt>"))
    ]
}
