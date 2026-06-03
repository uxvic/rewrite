import Foundation

/// Routes rewrites through the locally installed `claude` CLI (Claude Code),
/// authenticated with the user's Claude subscription — no API key, no per-use
/// API billing. Requires Claude Code installed and logged in.
///
/// Note: uses Claude Code outside its intended (coding) purpose; the user's
/// explicit, informed choice. Output streams as the CLI prints it; cancellation
/// terminates the process.
struct ClaudeCodeProvider: RewriteProvider {
    let configuredPath: String

    private static var candidatePaths: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.claude/local/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude"
        ]
    }

    private func resolveExecutable() -> String? {
        let fm = FileManager.default
        let trimmed = configuredPath.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, fm.isExecutableFile(atPath: trimmed) { return trimmed }
        return Self.candidatePaths.first { fm.isExecutableFile(atPath: $0) }
    }

    func stream(text: String,
                systemPrompt: String,
                onDelta: @Sendable @escaping (String) -> Void) async throws -> String {
        guard let exe = resolveExecutable() else { throw RewriteError.claudeCodeNotFound }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = [
            "-p", text,
            "--append-system-prompt", systemPrompt,
            "--output-format", "text"
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    var collected = ""
                    outPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty, let piece = String(data: data, encoding: .utf8) else { return }
                        collected += piece
                        onDelta(piece)
                    }

                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: RewriteError.claudeCodeFailed("Couldn't launch claude: \(error.localizedDescription)"))
                        return
                    }

                    process.waitUntilExit()
                    outPipe.fileHandleForReading.readabilityHandler = nil

                    let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    if process.terminationStatus != 0 {
                        let detail = errText.isEmpty ? "exit code \(process.terminationStatus)" : errText
                        continuation.resume(throwing: RewriteError.claudeCodeFailed(detail))
                        return
                    }
                    let result = collected.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !result.isEmpty else {
                        continuation.resume(throwing: RewriteError.empty)
                        return
                    }
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            process.terminate()
        }
    }

    func verify() async throws -> String {
        guard let exe = resolveExecutable() else { throw RewriteError.claudeCodeNotFound }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = ["--version"]
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do { try process.run() } catch {
                    continuation.resume(throwing: RewriteError.claudeCodeFailed("Couldn't launch claude: \(error.localizedDescription)"))
                    return
                }
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    let version = out.isEmpty ? "CLI found" : out
                    continuation.resume(returning: "Connected · \(version)")
                } else {
                    continuation.resume(throwing: RewriteError.claudeCodeFailed(err.isEmpty ? "exit code \(process.terminationStatus)" : err))
                }
            }
        }
    }
}
