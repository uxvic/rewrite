import Foundation

/// A preset rewriting action. Each case maps a button in the UI to a system
/// prompt that instructs the LLM how to transform the user's text.
enum RewriteAction: String, CaseIterable, Identifiable {
    case paraphrase
    case grammar
    case shorter
    case longer
    case professional
    case casual
    case friendly

    var id: String { rawValue }

    /// Short label shown on the button.
    var label: String {
        switch self {
        case .paraphrase:   return "Paraphrase"
        case .grammar:      return "Fix Grammar"
        case .shorter:      return "Shorter"
        case .longer:       return "Longer"
        case .professional: return "Professional"
        case .casual:       return "Casual"
        case .friendly:     return "Friendly"
        }
    }

    /// SF Symbol used on the button.
    var systemImage: String {
        switch self {
        case .paraphrase:   return "arrow.triangle.2.circlepath"
        case .grammar:      return "checkmark.circle"
        case .shorter:      return "arrow.down.right.and.arrow.up.left"
        case .longer:       return "arrow.up.left.and.arrow.down.right"
        case .professional: return "briefcase"
        case .casual:       return "cup.and.saucer"
        case .friendly:     return "hand.wave"
        }
    }

    /// The instruction sent to the model as the system prompt.
    var systemPrompt: String {
        let base = "You are a writing assistant. Rewrite the user's text following the instruction below. Return ONLY the rewritten text with no preamble, no quotes, and no explanation."
        let instruction: String
        switch self {
        case .paraphrase:
            instruction = "Paraphrase the text: reword it while preserving the original meaning and tone."
        case .grammar:
            instruction = "Correct only grammar, spelling, and punctuation. Keep the original wording, meaning, and tone intact wherever possible."
        case .shorter:
            instruction = "Make the text more concise and shorter while keeping the key meaning."
        case .longer:
            instruction = "Expand the text with more detail and elaboration while keeping the original meaning."
        case .professional:
            instruction = "Rewrite the text in a polished, professional tone suitable for business communication."
        case .casual:
            instruction = "Rewrite the text in a relaxed, casual tone."
        case .friendly:
            instruction = "Rewrite the text in a warm, friendly, approachable tone."
        }
        return base + "\n\nInstruction: " + instruction
    }

    /// Builds a system prompt for a free-form custom instruction.
    static func customSystemPrompt(_ instruction: String) -> String {
        "You are a writing assistant. Rewrite the user's text following this instruction. Return ONLY the rewritten text with no preamble, no quotes, and no explanation.\n\nInstruction: \(instruction)"
    }
}
