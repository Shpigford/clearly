import SwiftUI
import ClearlyCore

struct StatusBarView: View {
    @ObservedObject var state: StatusBarState
    var showsCounts: Bool = true
    var showsLargeDocumentMode: Bool = false
    var documentCharacterCount: Int = 0

    var body: some View {
        ZStack {
            if showsCounts {
                Text(label(for: state.counts))
                    .font(Theme.Typography.findCount)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack {
                Spacer()
                if showsLargeDocumentMode {
                    LargeDocumentModeIndicator(characterCount: documentCharacterCount)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xs)
        .frame(height: 28)
        .accessibilityElement(children: .contain)
    }

    private func label(for c: MarkdownStats.Counts) -> String {
        if c.totalWords == 0 && c.totalChars == 0 {
            return "Empty document"
        }
        if c.hasSelection {
            return "\(formatted(c.selectionWords)) \(pluralize("word", c.selectionWords)) selected"
                + " · \(formatted(c.selectionChars)) \(pluralize("character", c.selectionChars))"
        }
        return "\(formatted(c.totalWords)) \(pluralize("word", c.totalWords))"
            + " · \(formatted(c.totalChars)) \(pluralize("character", c.totalChars))"
            + " · \(readingTime(seconds: c.totalReadingSeconds))"
    }

    private func formatted(_ n: Int) -> String {
        n.formatted(.number)
    }

    private func pluralize(_ word: String, _ n: Int) -> String {
        n == 1 ? word : "\(word)s"
    }

    private func readingTime(seconds: Int) -> String {
        if seconds < 30 { return "Less than 1 min read" }
        let minutes = Int((Double(seconds) / 60.0).rounded())
        let bounded = max(1, minutes)
        return "\(bounded) min read"
    }
}

private struct LargeDocumentModeIndicator: View {
    let characterCount: Int

    @State private var showsExplanation = false

    var body: some View {
        Button {
            showsExplanation.toggle()
        } label: {
            Label("Large Document Mode", systemImage: "speedometer")
                .labelStyle(.titleAndIcon)
                .font(Theme.Typography.findCount)
                .foregroundStyle(Theme.warningColorSwiftUI)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Theme.warningColorSwiftUI.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .help("Large Document Mode is active")
        .accessibilityLabel("Large Document Mode")
        .accessibilityHint("Shows what changes for performance in large documents")
        .popover(isPresented: $showsExplanation, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Label("Large Document Mode", systemImage: "speedometer")
                    .font(.headline)

                Text("This document has \(formatted(characterCount)) characters, so Clearly changes a few editor behaviors to keep typing responsive.")
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    explanationRow("Live spelling, grammar, and autocorrect are disabled.")
                    explanationRow("Syntax highlighting waits until you pause typing.")
                    explanationRow("Word counts, outline, preview, and save-state updates may refresh after a short delay.")
                }
                .foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.lg)
            .frame(width: 340, alignment: .leading)
        }
    }

    private func explanationRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Theme.warningColorSwiftUI)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formatted(_ n: Int) -> String {
        n.formatted(.number)
    }
}
