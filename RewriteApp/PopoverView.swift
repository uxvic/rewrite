import SwiftUI

struct PopoverView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updater = UpdateChecker.shared
    @StateObject private var speech = SpeechManager()
    @State private var updateDismissed = false

    @State private var inputText = ""
    @State private var outputText = ""
    @State private var customInstruction = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var copied = false
    @State private var dictationBase = ""
    @State private var currentTask: Task<Void, Never>?

    private enum Panel { case main, settings, history }
    @State private var panel: Panel = .main

    @FocusState private var inputFocused: Bool

    private let actions = RewriteAction.allCases

    var body: some View {
        VStack(spacing: 0) {
            specBar
            HairlineDivider()
            if let up = updater.available, !updateDismissed {
                updateBanner(up)
                HairlineDivider()
            }
            Group {
                switch panel {
                case .main:     mainContent
                case .settings: SettingsView()
                case .history:  historyPanel
                }
            }
        }
        .frame(width: 380, height: 540)
        .background(Theme.bg)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { inputFocused = true }
        }
        .onChange(of: speech.transcript) { _, newValue in
            guard speech.isRecording else { return }
            let separator = dictationBase.isEmpty ? "" : " "
            inputText = dictationBase + separator + newValue
        }
    }

    // MARK: - Spec bar

    private var specBar: some View {
        HStack(spacing: 8) {
            Text("REWRITE").font(.display(16)).tracking(2).foregroundStyle(Theme.textPrimary)
            Text("v1").font(.mono(9)).tracking(2).foregroundStyle(Theme.textSecondary)
            Spacer()
            LEDDot(color: Theme.accent)
            Text(providerShortName.uppercased()).font(.mono(10)).tracking(2).foregroundStyle(Theme.textSecondary)
            Button { panel = (panel == .history) ? .main : .history } label: {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.textSecondary)
            }.buttonStyle(.borderless).help("History")
            Button { panel = (panel == .settings) ? .main : .settings } label: {
                Image(systemName: panel == .settings ? "chevron.left" : "gearshape").foregroundStyle(Theme.textSecondary)
            }.buttonStyle(.borderless).help("Settings")
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    private func updateBanner(_ up: UpdateInfo) -> some View {
        HStack(spacing: 8) {
            LEDDot(color: Theme.accent)
            Text("UPDATE AVAILABLE · v\(up.version)")
                .font(.mono(10)).tracking(1).foregroundStyle(Theme.textPrimary).lineLimit(1)
            Spacer()
            Button { updater.openDownload() } label: { Text("DOWNLOAD") }
                .buttonStyle(InstrumentButtonStyle(prominent: true)).controlSize(.small)
            Button { updateDismissed = true } label: {
                Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
            }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.surface)
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

    // MARK: - Main panel

    private var mainContent: some View {
        VStack(spacing: 14) {
            inputModule
            actionsModule
            customRow
            HairlineDivider()
            outputModule
        }
        .padding(16)
    }

    private var wordCount: Int {
        inputText.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }

    private var inputModule: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(text: "INPUT")
                Spacer()
                Text("\(wordCount) WORDS").font(.mono(10)).tracking(1.5).foregroundStyle(Theme.textSecondary)
            }
            ZStack(alignment: .bottomTrailing) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $inputText)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .focused($inputFocused)
                        .padding(8)
                        .frame(height: 96)
                    if inputText.isEmpty {
                        Text("Type, paste or dictate…")
                            .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                            .padding(12).allowsHitTesting(false)
                    }
                }
                Button {
                    if !speech.isRecording { dictationBase = inputText }
                    speech.toggle()
                } label: {
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(speech.isRecording ? Color.white : Theme.accentInk)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(speech.isRecording ? Theme.ledFail : Theme.accent))
                }
                .buttonStyle(.plain)
                .padding(8)
                .help(speech.isRecording ? "Stop dictation" : "Dictate")
            }
            .module(Theme.surface, focused: inputFocused)
        }
    }

    private var actionsModule: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "ACTIONS")
            let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    actionCell(index: String(format: "%02d", index + 1),
                               label: action.label.uppercased(),
                               key: index < 9 ? "⌘\(index + 1)" : nil) {
                        run(systemPrompt: action.systemPrompt, label: action.label)
                    }
                    .keyboardShortcut(shortcutKey(index), modifiers: .command)
                }
                ForEach(settings.customPresets) { preset in
                    actionCell(index: "•", label: preset.label.uppercased(), key: nil) {
                        run(systemPrompt: RewriteAction.customSystemPrompt(preset.instruction), label: preset.label)
                    }
                }
            }
        }
    }

    private func actionCell(index: String, label: String, key: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(index).font(.monoLabel(10)).foregroundStyle(Theme.accent)
                Text(label).font(.mono(11)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 4)
                if let key { Keycap(text: key) }
            }
            .padding(.vertical, 8).padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .module(Theme.panel)
        }
        .buttonStyle(.plain)
        .disabled(isInputEmpty || isLoading)
        .opacity(isInputEmpty || isLoading ? 0.5 : 1)
    }

    private func shortcutKey(_ index: Int) -> KeyEquivalent {
        guard index < 9 else { return .init("0") }
        return KeyEquivalent(Character("\(index + 1)"))
    }

    private var customRow: some View {
        HStack(spacing: 8) {
            TextField("Custom instruction…", text: $customInstruction)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .padding(.vertical, 9).padding(.horizontal, 10)
                .module(Theme.surface)
                .onSubmit(runCustom)
            Button(action: runCustom) { Text("GO") }
                .buttonStyle(InstrumentButtonStyle(prominent: true))
                .disabled(customInstruction.trimmingCharacters(in: .whitespaces).isEmpty || isInputEmpty || isLoading)
        }
    }

    private var outputModule: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(text: "OUTPUT")
                Spacer()
                if isLoading {
                    Text("STREAMING").font(.mono(10)).tracking(1.5).foregroundStyle(Theme.accent)
                    Button { currentTask?.cancel() } label: { Text("STOP") }
                        .buttonStyle(InstrumentButtonStyle())
                        .controlSize(.mini)
                } else {
                    Text(errorMessage == nil ? "READY" : "ERROR")
                        .font(.mono(10)).tracking(1.5)
                        .foregroundStyle(errorMessage == nil ? Theme.accent : Theme.ledFail)
                }
            }
            ScrollView {
                Text(errorMessage ?? (outputText.isEmpty ? "Result appears here." : outputText))
                    .font(.system(size: 13))
                    .foregroundStyle(errorMessage != nil ? Theme.ledFail :
                                        (outputText.isEmpty ? Theme.textSecondary : Theme.textPrimary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxHeight: .infinity)
            .module(Theme.surface)

            HStack(spacing: 8) {
                Button { copyToClipboard() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 12))
                        Text(copied ? "COPIED" : "COPY")
                    }
                }
                .buttonStyle(InstrumentButtonStyle())
                .disabled(outputText.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)

                Button { inputText = outputText; outputText = "" } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.up").font(.system(size: 12))
                        Text("USE AS INPUT")
                    }
                }
                .buttonStyle(InstrumentButtonStyle())
                .disabled(outputText.isEmpty)
                Spacer()
            }
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
                            Button {
                                inputText = item.input; outputText = item.output; panel = .main
                            } label: {
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

    // MARK: - Run

    private var isInputEmpty: Bool {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func run(systemPrompt: String, label: String) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        currentTask?.cancel()
        errorMessage = nil
        isLoading = true
        outputText = ""
        let provider = settings.makeProvider()

        currentTask = Task {
            do {
                let result = try await provider.stream(text: text, systemPrompt: systemPrompt) { piece in
                    Task { @MainActor in outputText += piece }
                }
                await MainActor.run {
                    outputText = result
                    isLoading = false
                    settings.addHistory(actionLabel: label, input: text, output: result)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    if !Task.isCancelled { errorMessage = error.localizedDescription }
                }
            }
        }
    }

    private func runCustom() {
        let instruction = customInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        run(systemPrompt: RewriteAction.customSystemPrompt(instruction), label: "Custom: \(instruction)")
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}
