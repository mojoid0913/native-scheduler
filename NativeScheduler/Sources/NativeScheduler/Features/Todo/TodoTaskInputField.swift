import AppKit
import SwiftUI

struct TodoTaskInputField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onSubmit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13, weight: .regular)
        field.textColor = NSColor(Color.nsTextPrimary)
        field.placeholderString = "Add task..."
        field.cell?.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingTail
        field.setAccessibilityLabel("New task title")
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.update(
            text: $text,
            isFocused: $isFocused,
            onSubmit: onSubmit
        )
        if field.stringValue != text {
            field.stringValue = text
        }
        guard isFocused, field.window?.firstResponder !== field.currentEditor() else {
            return
        }
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        private var text: Binding<String>
        private var isFocused: Binding<Bool>
        private var onSubmit: (String) -> Void

        init(
            text: Binding<String>,
            isFocused: Binding<Bool>,
            onSubmit: @escaping (String) -> Void
        ) {
            self.text = text
            self.isFocused = isFocused
            self.onSubmit = onSubmit
        }

        func update(
            text: Binding<String>,
            isFocused: Binding<Bool>,
            onSubmit: @escaping (String) -> Void
        ) {
            self.text = text
            self.isFocused = isFocused
            self.onSubmit = onSubmit
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isFocused.wrappedValue = true
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isFocused.wrappedValue = false
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)),
                  let field = control as? NSTextField
            else {
                return false
            }
            submit(field)
            return true
        }

        @objc func submit(_ field: NSTextField) {
            let submittedTitle = field.stringValue
            text.wrappedValue = ""
            field.stringValue = ""
            DispatchQueue.main.async { [weak self] in
                self?.onSubmit(submittedTitle)
            }
        }
    }
}
