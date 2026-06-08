import SwiftUI

struct PopoverView: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var speech = SpeechManager()

    @State private var inputText = ""
    @State private var outputText = ""
    @State private var customInstruction = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var copied = false
    @State private var dictationBase = ""
    @State private var currentTask: Task<Void, Never>?
    @State private var justFinished = false
    @State private var pulse = false
    @State private var lastSystemPrompt: String?
    @State private var lastLabel = ""
    @State private var showDiff = false
    @State private var fromClipboard = false
    @State private var lastClipboardCount = -1
    @State private var diffInput = ""
    @State private var voiceMode = false

    private enum Panel { case main, settings, history }
    @State private var panel: Panel = .main

    @State private var inputFocused = false

    var body: some View {
        Group {
            if voiceMode {
                VoiceOverlayView(speech: speech, onDone: finishVoice, onCancel: cancelVoice)
            } else {
                VStack(spacing: 0) {
                    specBar
                    HairlineDivider()
                    if panel == .main {
                        modeSwitcher
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
            }
        }
        .frame(width: 380, height: 668)
        .background(Theme.bg)
        .onAppear {
            autoFillFromClipboard()
        }
        .onChange(of: settings.mode) { _, _ in showDiff = false }
        .onChange(of: speech.transcript) { _, newValue in
            guard speech.isRecording, !voiceMode else { return }
            let separator = dictationBase.isEmpty ? "" : " "
            inputText = dictationBase + separator + newValue
        }
        .onChange(of: speech.isRecording) { _, recording in
            if recording {
                pulse = false
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
            } else {
                withAnimation(.default) { pulse = false }
            }
        }
    }

    // MARK: - Spec bar

    private var specBar: some View {
        HStack(spacing: 8) {
            Text("REWRITE").font(.display(16)).tracking(2).foregroundStyle(Theme.textPrimary)
            Text("v\(appVersion)").font(.mono(9)).tracking(1).foregroundStyle(Theme.textSecondary)
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

    private var providerShortName: String {
        switch settings.provider {
        case .appleOnDevice: return "On-device"
        case .hosted:        return "Free"
        case .anthropic:     return "Claude"
        case .claudeCode:    return "Claude Code"
        case .ollama:        return "Ollama"
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Mode switcher

    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(RewriteMode.allCases) { m in
                let active = settings.mode == m
                Button { settings.mode = m } label: {
                    Text(m.title)
                        .font(.monoLabel(11)).tracking(2)
                        .foregroundStyle(active ? Theme.accentInk : Theme.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(active ? Theme.accent : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: Metric.radius).stroke(Theme.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Metric.radius))
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - Main panel

    private var mainContent: some View {
        VStack(spacing: 12) {
            inputModule
            outputModule
            HairlineDivider()
            actionsModule
            customRow
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
                if speech.isRecording {
                    HStack(spacing: 5) {
                        Circle().fill(Theme.ledFail).frame(width: 7, height: 7).opacity(pulse ? 0.25 : 1)
                        Text("REC").font(.mono(10)).tracking(2).foregroundStyle(Theme.ledFail)
                    }
                } else if fromClipboard {
                    Button { fromClipboard = false; inputText = "" } label: {
                        HStack(spacing: 4) {
                            Text("FROM CLIPBOARD").font(.mono(9)).tracking(1)
                            Image(systemName: "xmark").font(.system(size: 8))
                        }
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                    }.buttonStyle(.plain).help("Clear")
                } else {
                    Text("\(wordCount) WORDS").font(.mono(10)).tracking(1.5).foregroundStyle(Theme.textSecondary)
                }
            }
            ZStack(alignment: .bottomTrailing) {
                ZStack(alignment: .topLeading) {
                    AutoScrollTextEditor(text: $inputText, isFocused: $inputFocused,
                                         font: .systemFont(ofSize: 13), textColor: Theme.nsTextPrimary,
                                         autoScroll: speech.isRecording, autoFocus: true)
                        .frame(height: 78)
                    if inputText.isEmpty {
                        Text(settings.mode.inputPlaceholder)
                            .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 13).padding(.vertical, 12).allowsHitTesting(false)
                    }
                }
                micButton.padding(8)
            }
            .module(Theme.surface, focused: inputFocused || speech.isRecording)
        }
    }

    private var micButton: some View {
        Button { enterVoiceMode() } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.accentInk)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.accent))
        }
        .buttonStyle(.plain)
        .help("Voice input")
    }

    private func enterVoiceMode() {
        dictationBase = inputText
        if !speech.isRecording { speech.toggle() }
        voiceMode = true
    }

    private func finishVoice() {
        let captured = speech.transcript
        if speech.isRecording { speech.stop() }
        let sep = dictationBase.isEmpty ? "" : " "
        inputText = captured.isEmpty ? dictationBase : dictationBase + sep + captured
        voiceMode = false
        fromClipboard = false
    }

    private func cancelVoice() {
        if speech.isRecording { speech.stop() }
        voiceMode = false
    }

    private var actionsModule: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "ACTIONS")
            let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(settings.mode.actions.enumerated()), id: \.element.id) { index, action in
                    actionCell(index: String(format: "%02d", index + 1),
                               icon: action.systemImage,
                               label: action.label.uppercased(),
                               key: index < 9 ? "⌘\(index + 1)" : nil) {
                        run(systemPrompt: action.systemPrompt, label: action.label)
                    }
                    .keyboardShortcut(shortcutKey(index), modifiers: .command)
                }
                ForEach(settings.customPresets) { preset in
                    actionCell(index: "★", icon: "star", label: preset.label.uppercased(), key: nil) {
                        run(systemPrompt: RewriteAction.customSystemPrompt(preset.instruction), label: preset.label)
                    }
                }
            }
        }
    }

    private func actionCell(index: String, icon: String, label: String, key: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(index).font(.monoLabel(10)).foregroundStyle(Theme.accent)
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).frame(width: 14)
                Text(label).font(.mono(11)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 2)
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
            TextField(settings.mode.customHint, text: $customInstruction)
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
                    Text(errorMessage != nil ? "ERROR" : (justFinished ? "DONE" : "READY"))
                        .font(.mono(10)).tracking(1.5)
                        .foregroundStyle(errorMessage != nil ? Theme.ledFail : Theme.accent)
                }
            }
            ScrollView {
                Group {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(Theme.ledFail)
                    } else if outputText.isEmpty {
                        Text("Result appears here.").foregroundStyle(Theme.textSecondary)
                    } else if showDiff {
                        diffText
                    } else {
                        Text(outputText).foregroundStyle(Theme.textPrimary)
                    }
                }
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
            }
            .frame(height: 124)
            .module(Theme.surface, focused: justFinished)

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

                Button { inputText = outputText; outputText = ""; showDiff = false } label: {
                    Image(systemName: "arrow.up").font(.system(size: 12))
                }
                .buttonStyle(InstrumentButtonStyle())
                .disabled(outputText.isEmpty)
                .help("Use as input")

                Button { regenerate() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12))
                }
                .buttonStyle(InstrumentButtonStyle())
                .disabled(lastSystemPrompt == nil || isLoading || isInputEmpty)
                .help("Regenerate (a fresh variation)")

                Spacer()

                // RESULT | DIFF toggle
                HStack(spacing: 0) {
                    ForEach(["RESULT", "DIFF"], id: \.self) { opt in
                        let on = (opt == "DIFF") == showDiff
                        Button { showDiff = (opt == "DIFF") } label: {
                            Text(opt).font(.mono(9)).tracking(1)
                                .foregroundStyle(on ? Theme.accentInk : Theme.textSecondary)
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(on ? Theme.accent : Color.clear)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.hairline, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .opacity(outputText.isEmpty ? 0.4 : 1)
                .disabled(outputText.isEmpty)
            }
        }
    }

    private var diffText: Text {
        TextDiff.words(old: diffInput, new: outputText).reduce(Text("")) { acc, seg in
            switch seg.kind {
            case .same:    return acc + Text(seg.text).foregroundColor(Theme.textPrimary)
            case .added:   return acc + Text(seg.text).foregroundColor(Theme.accent)
            case .removed: return acc + Text(seg.text).foregroundColor(Theme.ledFail).strikethrough()
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

    private func run(systemPrompt: String, label: String, variation: Bool = false) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        currentTask?.cancel()
        errorMessage = nil
        isLoading = true
        outputText = ""
        showDiff = false
        fromClipboard = false
        lastSystemPrompt = systemPrompt
        lastLabel = label
        diffInput = text
        let provider = settings.makeProvider()
        var payload = RewriteAction.wrap(text)
        if variation { payload += "\n\n(Give a noticeably different alternative version.)" }

        currentTask = Task {
            do {
                let raw = try await provider.stream(text: payload, systemPrompt: systemPrompt) { piece in
                    Task { @MainActor in outputText += piece }
                }
                let result = RewriteAction.clean(raw)
                await MainActor.run {
                    outputText = result
                    isLoading = false
                    settings.addHistory(actionLabel: label, input: text, output: result)
                    if settings.autoCopyResult { copyToClipboard() }
                    withAnimation(.easeOut(duration: 0.25)) { justFinished = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation(.easeIn(duration: 0.5)) { justFinished = false }
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    if !Task.isCancelled { errorMessage = error.localizedDescription }
                }
            }
        }
    }

    private func regenerate() {
        guard let sp = lastSystemPrompt else { return }
        run(systemPrompt: sp, label: lastLabel, variation: true)
    }

    private func autoFillFromClipboard() {
        guard settings.autoFillClipboard, isInputEmpty else { return }
        let pb = NSPasteboard.general
        guard pb.changeCount != lastClipboardCount else { return }
        lastClipboardCount = pb.changeCount
        if let s = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty, s.count <= 8000 {
            inputText = s
            fromClipboard = true
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
