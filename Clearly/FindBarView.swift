import SwiftUI
import ClearlyCore

struct FindBarView: View {
    @ObservedObject var findState: FindState
    @State private var isFieldFocused = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))

                FindQueryField(
                    text: $findState.query,
                    focusRequest: findState.focusRequest,
                    isFocused: $isFieldFocused,
                    onSubmitNext: { findState.navigateToNext?() },
                    onSubmitPrevious: { findState.navigateToPrevious?() },
                    onEscape: { findState.isVisible = false }
                )
                .frame(minWidth: 120)

                if !findState.query.isEmpty {
                    if findState.matchCount > 0 {
                        Text("\(findState.currentIndex) of \(findState.matchCount)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text("No results")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor.opacity(isFieldFocused ? 0.4 : 0), lineWidth: 1)
                    .animation(Theme.Motion.hover, value: isFieldFocused)
            )

            HStack(spacing: 2) {
                FindNavButton(icon: "chevron.left", disabled: findState.matchCount == 0) {
                    findState.navigateToPrevious?()
                }
                FindNavButton(icon: "chevron.right", disabled: findState.matchCount == 0) {
                    findState.navigateToNext?()
                }
            }

            Button("Done") {
                findState.dismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.backgroundColorSwiftUI)
        .onAppear {
            isFieldFocused = true
        }
        .onChange(of: findState.focusRequest) { _, _ in
            isFieldFocused = true
        }
    }
}

private struct FindNavButton: View {
    let icon: String
    let disabled: Bool
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(disabled ? .quaternary : (isHovering ? .primary : .secondary))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering && !disabled
                            ? Color.primary.opacity(colorScheme == .dark ? Theme.hoverOpacityDark : Theme.hoverOpacity)
                            : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering in
            withAnimation(Theme.Motion.hover) {
                isHovering = hovering
            }
        }
    }
}

private struct FindQueryField: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: UUID
    @Binding var isFocused: Bool
    let onSubmitNext: () -> Void
    let onSubmitPrevious: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 13)
        textField.placeholderString = "Find"
        textField.lineBreakMode = .byClipping
        textField.delegate = context.coordinator
        context.coordinator.attach(textField)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attach(textField)
        if textField.stringValue != text {
            context.coordinator.isApplyingSwiftUpdate = true
            textField.stringValue = text
            context.coordinator.isApplyingSwiftUpdate = false
        }

        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                guard let window = textField.window else { return }
                window.makeFirstResponder(textField)
                textField.currentEditor()?.selectAll(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FindQueryField
        var lastFocusRequest: UUID?
        var isApplyingSwiftUpdate = false
        weak var textField: NSTextField?
        private var commandMonitor: Any?

        init(parent: FindQueryField) {
            self.parent = parent
        }

        deinit {
            if let commandMonitor {
                NSEvent.removeMonitor(commandMonitor)
            }
        }

        func attach(_ textField: NSTextField) {
            self.textField = textField
            guard commandMonitor == nil else { return }

            commandMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      self.parent.isFocused,
                      let textField = self.textField,
                      textField.window?.isKeyWindow == true else {
                    return event
                }

                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                switch (modifiers, event.charactersIgnoringModifiers) {
                case (.command, "a"):
                    textField.window?.makeFirstResponder(textField)
                    textField.currentEditor()?.selectAll(nil)
                    return nil
                case (.command, "v"):
                    guard let pasted = NSPasteboard.general.string(forType: .string) else {
                        return event
                    }
                    textField.window?.makeFirstResponder(textField)
                    if let editor = textField.currentEditor() {
                        editor.insertText(pasted)
                        self.parent.text = textField.stringValue
                    } else {
                        textField.stringValue = pasted
                        self.parent.text = pasted
                    }
                    return nil
                default:
                    return event
                }
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.isFocused = true
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.isFocused = false
        }

        func controlTextDidChange(_ obj: Notification) {
            guard !isApplyingSwiftUpdate,
                  let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertLineBreak(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    parent.onSubmitPrevious()
                } else {
                    parent.onSubmitNext()
                }
                return true
            default:
                return false
            }
        }
    }
}
