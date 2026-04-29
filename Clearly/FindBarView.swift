import SwiftUI
import ClearlyCore

struct FindBarView: View {
    @ObservedObject var findState: FindState
    @State private var isFieldFocused = false
    @State private var isReplaceFieldFocused = false
    @Environment(\.colorScheme) private var colorScheme

    private var hasRegexError: Bool { findState.activeMode == .edit && findState.regexError != nil }
    private var isReplaceVisible: Bool { findState.showReplace && findState.activeMode == .edit }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            findRow
            if isReplaceVisible {
                replaceRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.backgroundColorSwiftUI)
        .animation(Theme.Motion.smooth, value: findState.showReplace)
        .onAppear { isFieldFocused = true }
        .onChange(of: findState.focusRequest) { _, _ in
            isFieldFocused = true
            isReplaceFieldFocused = false
        }
        .onChange(of: findState.replaceFocusRequest) { _, _ in
            isReplaceFieldFocused = true
            isFieldFocused = false
        }
    }

    private var findRow: some View {
        HStack(spacing: 8) {
            DisclosureChevron(isExpanded: isReplaceVisible) {
                if findState.activeMode == .preview {
                    WorkspaceManager.shared.currentViewMode = .edit
                    findState.showReplace = true
                } else {
                    findState.showReplace.toggle()
                }
                findState.lastReplaceCount = nil
            }

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
                    onEscape: { findState.dismiss() }
                )
                .frame(minWidth: 120)

                if findState.activeMode == .edit {
                    FindOptionToggle(label: "Aa", isOn: $findState.caseSensitive)
                    FindOptionToggle(label: ".*", isOn: $findState.useRegex)
                }

                statusText
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: 1)
                    .animation(Theme.Motion.hover, value: isFieldFocused)
                    .animation(Theme.Motion.hover, value: hasRegexError)
            )
            .help(hasRegexError ? (findState.regexError ?? "") : "")

            HStack(spacing: 2) {
                FindNavButton(icon: "chevron.left", disabled: !findState.canNavigate) {
                    findState.navigateToPrevious?()
                }
                FindNavButton(icon: "chevron.right", disabled: !findState.canNavigate) {
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
    }

    private var replaceRow: some View {
        HStack(spacing: 8) {
            // Invisible spacer that matches the chevron column width so the
            // replace field aligns horizontally with the find field.
            Color.clear.frame(width: 20, height: 20)

            HStack(spacing: 4) {
                Image(systemName: "arrow.uturn.forward")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))

                ReplaceField(
                    text: $findState.replacementText,
                    focusRequest: findState.replaceFocusRequest,
                    isFocused: $isReplaceFieldFocused,
                    onReplace: { findState.editorPerformReplace?() },
                    onReplaceAll: { findState.editorPerformReplaceAll?() },
                    onSubmitPrevious: { findState.navigateToPrevious?() },
                    onEscape: { findState.dismiss() }
                )
                .frame(minWidth: 120)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor.opacity(isReplaceFieldFocused ? 0.4 : 0), lineWidth: 1)
                    .animation(Theme.Motion.hover, value: isReplaceFieldFocused)
            )

            Button("Replace All") { findState.editorPerformReplaceAll?() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(findState.canReplaceAll ? Color.accentColor : Color.secondary)
                .disabled(!findState.canReplaceAll)

            Button("Replace") { findState.editorPerformReplace?() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(findState.canReplace ? Color.accentColor : Color.secondary)
                .disabled(!findState.canReplace)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if let count = findState.lastReplaceCount {
            Text(count == 1 ? "Replaced 1 occurrence" : "Replaced \(count) occurrences")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else if hasRegexError, let error = findState.regexError {
            Text(error)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.red.opacity(0.8))
                .lineLimit(1)
        } else if !findState.query.isEmpty && !findState.resultsAreStale {
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

    private var borderColor: Color {
        if hasRegexError { return Color.red.opacity(0.5) }
        if isFieldFocused { return Color.accentColor.opacity(0.4) }
        return Color.clear
    }
}

private struct DisclosureChevron: View {
    let isExpanded: Bool
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isHovering ? .primary : .secondary)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovering
                            ? Color.primary.opacity(colorScheme == .dark ? Theme.hoverOpacityDark : Theme.hoverOpacity)
                            : Color.clear)
                )
                .contentShape(Rectangle())
                .animation(Theme.Motion.smooth, value: isExpanded)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Theme.Motion.hover) { isHovering = hovering }
        }
        .help(isExpanded ? "Hide replace" : "Show replace")
    }
}

private struct FindOptionToggle: View {
    let label: String
    @Binding var isOn: Bool
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: { isOn.toggle() }) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(isOn ? Color.accentColor : (isHovering ? .primary : .secondary))
                .frame(width: 20, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(backgroundFill)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Theme.Motion.hover) { isHovering = hovering }
        }
    }

    private var backgroundFill: Color {
        if isOn {
            return Color.accentColor.opacity(0.18)
        }
        if isHovering {
            return Color.primary.opacity(colorScheme == .dark ? Theme.hoverOpacityDark : Theme.hoverOpacity)
        }
        return Color.clear
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

private struct ReplaceField: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: UUID
    @Binding var isFocused: Bool
    let onReplace: () -> Void
    let onReplaceAll: () -> Void
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
        textField.placeholderString = "Replace"
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
        var parent: ReplaceField
        var lastFocusRequest: UUID?
        var isApplyingSwiftUpdate = false
        weak var textField: NSTextField?
        private var commandMonitor: Any?

        init(parent: ReplaceField) { self.parent = parent }

        deinit {
            if let commandMonitor { NSEvent.removeMonitor(commandMonitor) }
        }

        func attach(_ textField: NSTextField) {
            self.textField = textField
            guard commandMonitor == nil else { return }
            commandMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      self.parent.isFocused,
                      let textField = self.textField,
                      textField.window?.isKeyWindow == true else { return event }

                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let chars = event.charactersIgnoringModifiers ?? ""

                // ⌃⌥Return = Replace All
                if (chars == "\r" || chars == "\u{3}") && modifiers.contains(.control) && modifiers.contains(.option) {
                    self.parent.onReplaceAll()
                    return nil
                }

                switch (modifiers, chars) {
                case (.command, "a"):
                    textField.window?.makeFirstResponder(textField)
                    textField.currentEditor()?.selectAll(nil)
                    return nil
                case (.command, "v"):
                    guard let pasted = NSPasteboard.general.string(forType: .string) else { return event }
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

        func controlTextDidBeginEditing(_ obj: Notification) { parent.isFocused = true }
        func controlTextDidEndEditing(_ obj: Notification) { parent.isFocused = false }

        func controlTextDidChange(_ obj: Notification) {
            guard !isApplyingSwiftUpdate, let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertLineBreak(_:)):
                let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                if modifiers.contains(.shift) {
                    parent.onSubmitPrevious()
                } else {
                    parent.onReplace()
                }
                return true
            default:
                return false
            }
        }
    }
}
