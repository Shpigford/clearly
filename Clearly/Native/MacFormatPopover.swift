import SwiftUI
import AppKit
import ClearlyCore

/// Apple-Notes-style Aa format popover. Each button inserts or wraps
/// markdown syntax at the current selection by firing the same `@objc`
/// ClearlyTextView actions the keyboard shortcuts use, so popover and
/// shortcuts share one code path and markdown stays the single source of
/// truth.
struct MacFormatPopover: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Format")
                .font(.headline)

            // Row 1 — Heading level (cycles) + inline emphasis
            HStack(spacing: 8) {
                styleButton(systemImage: "number", help: "Cycle heading (⇧⌘H)") {
                    send(.heading, #selector(ClearlyTextView.insertHeading(_:)))
                }
                Divider().frame(height: 22)
                styleButton(systemImage: "bold", help: "Bold (⌘B)") {
                    send(.bold, #selector(ClearlyTextView.toggleBold(_:)))
                }
                styleButton(systemImage: "italic", help: "Italic (⌘I)") {
                    send(.italic, #selector(ClearlyTextView.toggleItalic(_:)))
                }
                styleButton(systemImage: "strikethrough", help: "Strikethrough (⇧⌘X)") {
                    send(.strikethrough, #selector(ClearlyTextView.toggleStrikethrough(_:)))
                }
                styleButton(systemImage: "chevron.left.forwardslash.chevron.right", help: "Inline code") {
                    send(.inlineCode, #selector(ClearlyTextView.toggleInlineCode(_:)))
                }
            }

            // Row 2 — Lists + structural blocks
            HStack(spacing: 8) {
                styleButton(systemImage: "list.bullet", help: "Bulleted list") {
                    send(.bulletList, #selector(ClearlyTextView.toggleBulletList(_:)))
                }
                styleButton(systemImage: "list.number", help: "Numbered list") {
                    send(.numberedList, #selector(ClearlyTextView.toggleNumberedList(_:)))
                }
                styleButton(systemImage: "checklist", help: "Checklist") {
                    send(.todoList, #selector(ClearlyTextView.toggleTodoList(_:)))
                }
                Divider().frame(height: 22)
                styleButton(systemImage: "text.quote", help: "Quote") {
                    send(.blockquote, #selector(ClearlyTextView.toggleBlockquote(_:)))
                }
                styleButton(systemImage: "tablecells", help: "Table") {
                    send(.table, #selector(ClearlyTextView.insertMarkdownTable(_:)))
                }
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func styleButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 30, height: 26)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func send(_ command: LiveEditorCommand, _ selector: Selector) {
        performFormattingCommand(command, selector: selector)
        // Keep popover open so users can apply multiple formats in sequence.
    }
}
