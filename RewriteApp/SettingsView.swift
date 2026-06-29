import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var newPresetLabel = ""
    @State private var newPresetInstruction = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionLabel(text: "Settings")

                providerSection
                ConnectionRow()
                HairlineDivider()
                switch settings.provider {
                case .appleOnDevice: appleOnDeviceSettings
                case .hosted:        hostedSettings
                case .anthropic:     anthropicSettings
                case .claudeCode:    claudeCodeSettings
                case .ollama:        ollamaSettings
                }
                HairlineDivider()
                generalSection
                HairlineDivider()
                presetsSection
                HairlineDivider()
                updatesSection
                HairlineDivider()
                Link("Privacy Policy", destination: URL(string: "https://uxvic.github.io/rewrite/privacy.html")!)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ambientBackground()
    }

    // MARK: helpers

    private func desc(_ s: String) -> some View {
        Text(s).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func fieldLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .semibold)).tracking(0.3).foregroundStyle(Theme.textSecondary)
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Provider")
            Picker("", selection: $settings.provider) {
                ForEach(LLMProvider.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.radioGroup).labelsHidden()
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "General")
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
                .font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
            Toggle("Sound when recording starts/stops", isOn: $settings.recordingSounds)
                .font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
            Toggle("Pre-fill from clipboard on open", isOn: $settings.autoFillClipboard)
                .font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
            Toggle("Copy result automatically", isOn: $settings.autoCopyResult)
                .font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
            Toggle("Smart send (rewrite vs. fulfill a request)", isOn: $settings.smartIntent)
                .font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
            desc("With Smart on, a plain send in Writing figures out whether you gave it text to polish or a request to carry out (e.g. “draft an email…”) and does the right thing. Explicit styles always rewrite literally.")
            desc("Pre-fill reads your clipboard when the popover opens; macOS may briefly show a “pasted from…” note. Turn it off here if you prefer.")
            hotkeyRow("OPEN POPOVER", selection: $settings.popoverHotKeyID)
            hotkeyRow("REWRITE SELECTION", selection: $settings.inPlaceHotKeyID)
            HStack {
                fieldLabel("IN-PLACE ACTION").frame(width: 140, alignment: .leading)
                Picker("", selection: $settings.defaultInPlaceAction) {
                    ForEach(RewriteAction.allCases) { Text($0.label).tag($0) }
                }.labelsHidden()
            }
            desc("“Rewrite selection” grabs highlighted text in any app, rewrites it with the in-place action, and pastes it back. Needs Accessibility permission (prompted on first use).")
        }
    }

    private func hotkeyRow(_ label: String, selection: Binding<String>) -> some View {
        HStack {
            fieldLabel(label).frame(width: 140, alignment: .leading)
            Picker("", selection: selection) {
                ForEach(HotKeyCombo.all) { Text($0.name).tag($0.id) }
            }.labelsHidden()
        }
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Custom presets")
            ForEach(settings.customPresets) { preset in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(preset.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Text(preset.instruction).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    Spacer()
                    Button(role: .destructive) { settings.removeCustomPreset(preset) } label: {
                        Image(systemName: "trash").foregroundStyle(Theme.ledFail)
                    }.buttonStyle(.borderless)
                }
                .padding(10).module(Theme.panel)
            }
            TextField("Button label (e.g. Excited)", text: $newPresetLabel).textFieldStyle(CapsuleFieldStyle())
            TextField("Instruction (e.g. rewrite with high energy)", text: $newPresetInstruction).textFieldStyle(CapsuleFieldStyle())
            Button { addPreset() } label: { Text("ADD PRESET") }
                .buttonStyle(InstrumentButtonStyle())
                .disabled(newPresetLabel.trimmingCharacters(in: .whitespaces).isEmpty
                          || newPresetInstruction.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Updates")
            HStack {
                Text("VERSION \(AppUpdater.shared.currentVersion)")
                    .font(.mono(10)).tracking(1).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button { AppUpdater.shared.checkForUpdates() } label: { Text("CHECK FOR UPDATES") }
                    .buttonStyle(InstrumentButtonStyle()).controlSize(.small)
            }
            desc("Rewrite updates itself automatically — you'll get a prompt when a new version is ready.")
        }
    }

    private func addPreset() {
        let label = newPresetLabel.trimmingCharacters(in: .whitespaces)
        let instruction = newPresetInstruction.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, !instruction.isEmpty else { return }
        settings.addCustomPreset(label: label, instruction: instruction)
        newPresetLabel = ""; newPresetInstruction = ""
    }

    private var appleOnDeviceSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Built-in AI · On-device", color: Theme.textPrimary)
            desc("Powered by Apple's on-device model. No key, no account, no internet — fully private and free. Works on Apple-Silicon Macs with macOS 26 and Apple Intelligence enabled.")
            if AppleOnDeviceProvider.isAvailable {
                HStack(spacing: 6) {
                    LEDDot(color: Theme.accent)
                    Text("READY · NOTHING TO SET UP").font(.mono(10)).tracking(1).foregroundStyle(Theme.accent)
                }
            } else {
                HStack(alignment: .top, spacing: 6) {
                    LEDDot(color: Theme.ledFail)
                    desc(AppleOnDeviceProvider.unavailableMessage)
                }
                Button { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!) } label: {
                    Text("OPEN APPLE INTELLIGENCE SETTINGS")
                }.buttonStyle(InstrumentButtonStyle()).controlSize(.small)
            }
        }
    }

    private var hostedSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Free models · Newsletter", color: Theme.textPrimary)
            desc("No API key needed. Sign in with your email to use models powered by the Rewrite gateway. Signing in adds you to the newsletter.")
            HostedSignInView()
            DisclosureGroup {
                fieldLabel("GATEWAY URL")
                TextField("https://…workers.dev", text: $settings.gatewayBaseURL).textFieldStyle(CapsuleFieldStyle())
            } label: {
                Text("Advanced").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            desc("Your text is sent to the gateway and the model provider to produce the rewrite.")
        }
    }

    private var anthropicSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Claude · Paid API", color: Theme.textPrimary)
            desc("Recommended. Fast, reliable, and the cost is tiny (a paragraph ≈ a fraction of a cent).")
            StepRow(1, "Open the Anthropic Console and sign in.") {
                Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                    Label("Get an API key", systemImage: "arrow.up.forward.square")
                }.font(.system(size: 12))
            }
            StepRow(2, "Add ~$5 credit under Billing, then create a key (starts with “sk-ant-”).")
            StepRow(3, "Paste the key below — stored only in your macOS Keychain.")
            SecureField("sk-ant-…", text: $settings.apiKey).textFieldStyle(CapsuleFieldStyle())
            fieldLabel("MODEL")
            Picker("", selection: $settings.anthropicModel) {
                ForEach(AppSettings.anthropicModels, id: \.self) { Text($0).tag($0) }
            }.labelsHidden()
            desc("Haiku is fastest & cheapest. Separate from a Claude.ai subscription.")
        }
    }

    private var claudeCodeSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Claude Code · Subscription", color: Theme.textPrimary)
            desc("Uses your Claude subscription via the claude CLI — no API key. Slower than the API.")
            StepRow(1, "Install Claude Code. Paste this into Terminal:")
            CommandRow("curl -fsSL https://claude.ai/install.sh | bash")
            StepRow(2, "Log in: run the command below, choose “Log in with your subscription”, then type /exit.")
            CommandRow("claude")
            StepRow(3, "Pick “Claude Code” above — the app finds the CLI automatically.")
            fieldLabel("PATH TO CLAUDE (OPTIONAL)")
            TextField("/Users/you/.claude/local/claude", text: $settings.claudeCodePath).textFieldStyle(CapsuleFieldStyle())
        }
    }

    private var ollamaSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Ollama · Free / Local", color: Theme.textPrimary)
            desc("Runs a model on your Mac. Free and private; no key or internet needed.")
            StepRow(1, "Install Ollama (or download from ollama.com):") {
                Link(destination: URL(string: "https://ollama.com/download")!) {
                    Label("ollama.com", systemImage: "arrow.up.forward.square")
                }.font(.system(size: 12))
            }
            CommandRow("brew install ollama")
            StepRow(2, "Download a model:")
            CommandRow("ollama pull llama3.2")
            StepRow(3, "Make sure Ollama is running:")
            CommandRow("ollama serve")
            fieldLabel("HOST")
            TextField("http://localhost:11434", text: $settings.ollamaHost).textFieldStyle(CapsuleFieldStyle())
            fieldLabel("MODEL")
            TextField("llama3.2", text: $settings.ollamaModel).textFieldStyle(CapsuleFieldStyle())
        }
    }
}

// MARK: - Hosted sign-in

struct HostedSignInView: View {
    @ObservedObject private var settings = AppSettings.shared
    private enum Stage { case email, code }
    @State private var stage: Stage = .email
    @State private var email = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @State private var info: String?
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.isSignedInToHosted {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        LEDDot(color: Theme.accent)
                        Text("Signed in · \(settings.hostedEmail)")
                            .font(.system(size: 11)).foregroundStyle(Theme.accent).lineLimit(1)
                        Spacer()
                        Button { signOut() } label: { Text("Sign out") }
                            .buttonStyle(InstrumentButtonStyle()).controlSize(.small)
                    }
                    Button { confirmDelete = true } label: {
                        Text(busy ? "Deleting…" : "Delete account")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ledFail)
                    }
                    .buttonStyle(.plain).disabled(busy)
                    .help("Removes your account from the gateway and unsubscribes you from the newsletter.")
                }
            } else {
                switch stage {
                case .email:
                    TextField("you@example.com", text: $email).textFieldStyle(CapsuleFieldStyle())
                    Button { start() } label: { Text(busy ? "Sending…" : "Send code") }
                        .buttonStyle(InstrumentButtonStyle(prominent: true))
                        .disabled(busy || !email.contains("@"))
                case .code:
                    desc("Enter the 6-digit code we emailed to \(email).")
                    TextField("123456", text: $code).textFieldStyle(CapsuleFieldStyle())
                    HStack {
                        Button { verify() } label: { Text(busy ? "Verifying…" : "Verify") }
                            .buttonStyle(InstrumentButtonStyle(prominent: true))
                            .disabled(busy || code.count != 6)
                        Button { resend() } label: { Text("Resend") }
                            .buttonStyle(InstrumentButtonStyle())
                            .disabled(busy)
                        Button { stage = .email; code = ""; error = nil; info = nil } label: { Text("Back") }
                            .buttonStyle(InstrumentButtonStyle())
                    }
                }
            }
            if let info {
                Text(info).font(.system(size: 11)).foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Text(error).font(.system(size: 11)).foregroundStyle(Theme.ledFail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Delete account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your sign-in from the gateway and unsubscribes \(settings.hostedEmail) from the newsletter. You can sign in again anytime.")
        }
    }

    private func desc(_ s: String) -> some View {
        Text(s).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func start() {
        busy = true; error = nil; info = nil
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        let url = settings.gatewayBaseURL
        Task {
            do {
                try await GatewayAuth.start(email: e, baseURL: url)
                await MainActor.run { email = e; stage = .code; busy = false; info = "Code sent to \(e)." }
            } catch {
                await MainActor.run { self.error = friendly(error); busy = false }
            }
        }
    }

    /// Re-request a code for the email already entered.
    private func resend() {
        guard !busy else { return }
        busy = true; error = nil; info = nil
        let e = email; let url = settings.gatewayBaseURL
        Task {
            do {
                try await GatewayAuth.start(email: e, baseURL: url)
                await MainActor.run { busy = false; info = "New code sent to \(e)." }
            } catch {
                await MainActor.run { self.error = friendly(error); busy = false }
            }
        }
    }

    private func verify() {
        busy = true; error = nil; info = nil
        let e = email; let c = code; let url = settings.gatewayBaseURL
        Task {
            do {
                let token = try await GatewayAuth.verify(email: e, code: c, baseURL: url)
                await MainActor.run {
                    settings.hostedToken = token
                    settings.hostedEmail = e
                    busy = false; code = ""; stage = .email
                }
            } catch {
                await MainActor.run { self.error = friendly(error); busy = false }
            }
        }
    }

    /// Map raw network failures (e.g. the placeholder gateway host not resolving)
    /// to a clearer explanation.
    private func friendly(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Couldn't reach the sign-in server — the free-models gateway isn't set up yet. "
                 + "Deploy the Worker in gateway/ and set its URL under Advanced. (\(ns.localizedDescription))"
        }
        return error.localizedDescription
    }

    private func signOut() {
        settings.hostedToken = ""
        settings.hostedEmail = ""
        stage = .email; email = ""; code = ""
    }

    private func deleteAccount() {
        busy = true; error = nil; info = nil
        let token = settings.hostedToken; let url = settings.gatewayBaseURL
        Task {
            do {
                try await GatewayAuth.deleteAccount(token: token, baseURL: url)
                await MainActor.run {
                    settings.hostedToken = ""; settings.hostedEmail = ""
                    stage = .email; email = ""; code = ""; busy = false
                    info = "Account deleted."
                }
            } catch {
                await MainActor.run { self.error = friendly(error); busy = false }
            }
        }
    }
}

// MARK: - Connection status

private struct ConnectionRow: View {
    @ObservedObject private var settings = AppSettings.shared
    private enum Status: Equatable { case idle, checking, ok(String), fail(String) }
    @State private var status: Status = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                indicator
                Spacer()
                Button { test() } label: { Text(status == .checking ? "TESTING…" : "TEST CONNECTION") }
                    .buttonStyle(InstrumentButtonStyle())
                    .controlSize(.small)
                    .disabled(status == .checking)
            }
            if case .fail(let message) = status {
                Text(message).font(.system(size: 11)).foregroundStyle(Theme.ledFail)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
        .onChange(of: settings.provider) { _, _ in status = .idle }
    }

    @ViewBuilder private var indicator: some View {
        switch status {
        case .idle:
            HStack(spacing: 6) { LEDDot(color: Theme.textSecondary); Text("NOT TESTED").font(.mono(10)).tracking(1).foregroundStyle(Theme.textSecondary) }
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("CHECKING…").font(.mono(10)).tracking(1).foregroundStyle(Theme.textSecondary) }
        case .ok(let detail):
            HStack(spacing: 6) { LEDDot(color: Theme.accent); Text("CONNECTED · \(detail.uppercased())").font(.mono(10)).tracking(1).foregroundStyle(Theme.accent).lineLimit(1) }
        case .fail:
            HStack(spacing: 6) { LEDDot(color: Theme.ledFail); Text("NOT CONNECTED").font(.mono(10)).tracking(1).foregroundStyle(Theme.ledFail) }
        }
    }

    private func test() {
        status = .checking
        let provider = settings.makeProvider()
        Task {
            do {
                let detail = try await provider.verify()
                let trimmed = detail.replacingOccurrences(of: "Connected · ", with: "")
                await MainActor.run { status = .ok(trimmed) }
            } catch {
                await MainActor.run { status = .fail(error.localizedDescription) }
            }
        }
    }
}

// MARK: - Step + command rows

private struct StepRow<Trailing: View>: View {
    let number: Int
    let text: String
    @ViewBuilder var trailing: Trailing
    init(_ number: Int, _ text: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.number = number; self.text = text; self.trailing = trailing()
    }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(String(format: "%02d", number)).font(.monoLabel(10)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(text).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                trailing
            }
            Spacer(minLength: 0)
        }
    }
}

private struct CommandRow: View {
    let command: String
    @State private var copied = false
    init(_ command: String) { self.command = command }
    var body: some View {
        HStack(spacing: 8) {
            Text(command).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? Theme.accent : Theme.textSecondary)
            }
            .buttonStyle(.borderless).help("Copy command")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .module(Theme.surface)
    }
}
