import SwiftUI
import AppKit

struct FocusableTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void
    var fontColor: NSColor
    var fontSize: CGFloat
    var bgColor: NSColor
    var onSizeChange: ((CGSize) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = AutoSizingTextView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textColor = fontColor
        textView.backgroundColor = bgColor
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.isRichText = false
        textView.alignment = .left
        textView.textContainerInset = NSSize(width: 4, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.insertionPointColor = .white
        textView.autoresizingMask = []
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.sizeToFit()

        context.coordinator.textView = textView
        context.coordinator.onSizeChange = onSizeChange

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! AutoSizingTextView
        // Only update text if it changed externally (not from user typing or IME)
        // hasMarkedText() returns true when IME has uncommitted candidate text
        if textView.string != text && !context.coordinator.isEditing && !textView.hasMarkedText() {
            textView.string = text
        }
        textView.textColor = fontColor
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.backgroundColor = bgColor
        textView.textContainerInset = NSSize(width: 4, height: 2)
        context.coordinator.onSizeChange = onSizeChange

        if textView.window != nil && !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        // Report size
        DispatchQueue.main.async {
            textView.invalidateIntrinsicContentSize()
            let size = textView.intrinsicContentSize
            context.coordinator.onSizeChange?(CGSize(width: size.width + 8, height: size.height + 4))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: FocusableTextEditor
        weak var textView: AutoSizingTextView?
        var didFocus = false
        var isEditing = false
        var onSizeChange: ((CGSize) -> Void)?

        init(_ parent: FocusableTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isEditing = true
            // Don't sync to parent during IME marked text input
            // to avoid SwiftUI re-render interrupting the input
            if textView.hasMarkedText() { return }
            parent.text = textView.string
            if let tv = textView as? AutoSizingTextView {
                tv.invalidateIntrinsicContentSize()
                let size = tv.intrinsicContentSize
                onSizeChange?(CGSize(width: size.width + 8, height: size.height + 4))
            }
        }

        func textViewDidEndEditing(_ notification: Notification) {
            isEditing = false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCommit()
                return true
            }
            return false
        }
    }
}

class AutoSizingTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let container = self.textContainer, let manager = self.layoutManager else {
            return NSSize(width: 40, height: 20)
        }
        manager.ensureLayout(for: container)
        let rect = manager.usedRect(for: container)
        return NSSize(width: max(40, rect.width), height: max(20, rect.height))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }
}
