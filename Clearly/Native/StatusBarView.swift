import SwiftUI
import ClearlyCore

struct StatusBarView: View {
    @ObservedObject var state: StatusBarState

    var body: some View {
        Text(label(for: state.counts))
            .font(Theme.Typography.findCount)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(height: 28)
            .accessibilityElement(children: .combine)
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
