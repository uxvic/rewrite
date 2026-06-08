import SwiftUI
import AppKit

/// An NSTextView-backed editor that (unlike SwiftUI's TextEditor) scrolls to the
/// end of the text while `autoScroll` is true — so live dictation keeps the
/// newest words in view instead of staying pinned at the top.
struct AutoScrollTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var font: NSFont
    var textColor: NSColor
    /// While true (e.g. during dictation), the view scrolls to the end on updates.
    var autoScroll: Bool
    /// Become first responder once when first shown.
    var autoFocus: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = font
        tv.textColor = textColor
        tv.insertionPointColor = textColor
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.string = text
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            tv.string = text
            tv.textColor = textColor   // re-applying string can drop attributes
        }
        tv.font = font
        tv.textColor = textColor
        if autoScroll {
            tv.scrollToEndOfDocument(nil)
        }
        if autoFocus && !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoScrollTextEditor
        var didFocus = false
        init(_ parent: AutoScrollTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
        func textDidBeginEditing(_ notification: Notification) { parent.isFocused = true }
        func textDidEndEditing(_ notification: Notification) { parent.isFocused = false }
    }
}
