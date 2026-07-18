import AppKit
import SwiftUI

struct FocusedAnswerField: NSViewRepresentable {
    @Binding var text: String
    let onTextChange: (String) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.font = .monospacedDigitSystemFont(ofSize: 32, weight: .medium)
        field.alignment = .center
        field.placeholderString = "Answer"
        field.focusRingType = .none
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = .controlBackgroundColor
        field.maximumNumberOfLines = 1
        field.wantsLayer = true
        field.layer?.cornerRadius = 14
        field.layer?.cornerCurve = .continuous
        field.layer?.borderWidth = 1.5
        field.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor
        field.layer?.masksToBounds = true
        field.setAccessibilityLabel("Answer")
        focus(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        focus(field)
    }

    private func focus(_ field: NSTextField) {
        DispatchQueue.main.async {
            guard field.window?.firstResponder !== field.currentEditor() else { return }
            field.window?.makeFirstResponder(field)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusedAnswerField

        init(parent: FocusedAnswerField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
            parent.onTextChange(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                control.window?.makeFirstResponder(control)
                return true
            }
            return false
        }
    }
}
