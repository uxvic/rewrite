import SwiftUI

/// The Clipboard peer destination in Rewrite's floating surface. It deliberately
/// owns only presentation and explicit user actions; monitoring and persistence
/// stay in `ClipboardStore`.
struct ClipboardHistoryView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject private var settings = AppSettings.shared

    let onCopy: (ClipboardItem) -> Void
    let onUse: (ClipboardItem) -> Void

    @State private var copiedItemID: UUID?
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            HairlineDivider().padding(.horizontal, 14)

            if store.items.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(store.items.indices), id: \.self) { index in
                            if index > 0 { HairlineDivider().padding(.leading, 14) }
                            clipboardRow(store.items[index])
                        }
                    }
                    .padding(.vertical, 4)
                    .background(OverlayScrollers())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlass(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .confirmationDialog("Clear Clipboard History?", isPresented: $showClearConfirmation,
                            titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { store.clear() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the text copies stored locally in Rewrite.")
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 1) {
                Text("Clipboard History")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(settings.clipboardHistoryEnabled ? itemCount : "Paused")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 12)

            if !store.items.isEmpty {
                Button("Clear") { showClearConfirmation = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 7).padding(.vertical, 5)
                    .contentShape(Capsule())
                    .accessibilityLabel("Clear clipboard history")
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: settings.clipboardHistoryEnabled ? "doc.on.clipboard" : "pause.circle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            Text(settings.clipboardHistoryEnabled ? "Clipboard history is ready." : "Clipboard history is paused.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(settings.clipboardHistoryEnabled
                 ? "Copies made while Rewrite is open appear here."
                 : "Turn it on in Settings to capture new copies.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var itemCount: String {
        let count = store.items.count
        return count == 1 ? "1 item" : "\(count) items"
    }

    private func clipboardRow(_ item: ClipboardItem) -> some View {
        HStack(spacing: 10) {
            Button { copy(item) } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.text)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(item.createdAt, style: .relative)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Image(systemName: copiedItemID == item.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(copiedItemID == item.id ? Theme.accent : Theme.textSecondary)
                        .frame(width: 14)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copiedItemID == item.id ? "Copied clipboard item" : "Copy clipboard item")

            Button { onUse(item) } label: {
                Text("Use")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.fillTranslucent.opacity(0.07)))
                    .overlay(Capsule().stroke(Theme.fillTranslucent.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use clipboard item in Rewrite")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func copy(_ item: ClipboardItem) {
        onCopy(item)
        withAnimation(.easeInOut(duration: 0.16)) { copiedItemID = item.id }
        let copiedID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard copiedItemID == copiedID else { return }
            withAnimation(.easeInOut(duration: 0.16)) { copiedItemID = nil }
        }
    }
}
