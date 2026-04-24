import SwiftUI
import ClearlyCore

/// Sheet that displays a Query's prose answer. The answer itself is plain
/// markdown — rendered here with SwiftUI's built-in AttributedString markdown
/// support (inline formatting) plus monospaced fallback for block content.
/// "File as Note" converts the answer into a WikiOperation and stages it on
/// the controller so the diff sheet takes over for review.
struct WikiAnswerSheet: View {
    @Bindable var controller: WikiOperationController
    let vaultRoot: URL?

    var body: some View {
        if let answer = controller.stagedAnswer {
            content(for: answer)
                .frame(minWidth: 640, minHeight: 480)
        }
    }

    @ViewBuilder
    private func content(for answer: WikiAnswer) -> some View {
        VStack(spacing: 0) {
            header(question: answer.question)
            Divider()
            ScrollView {
                renderedMarkdown(answer.markdown)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .textSelection(.enabled)
            }
            Divider()
            footer(answer: answer)
        }
    }

    private func header(question: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Answer")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(question)
                .font(.headline)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func footer(answer: WikiAnswer) -> some View {
        HStack(spacing: 12) {
            Text("Answers are not filed automatically. Use \"File as Note\" to save.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Copy") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(answer.markdown, forType: .string)
            }

            Button("File as Note") {
                fileAsNote(answer)
            }
            .disabled(vaultRoot == nil)

            Button("Close") {
                controller.dismissAnswer()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Rendering

    /// Render markdown as a stack of paragraphs/blocks. Each line is passed
    /// through AttributedString markdown for inline formatting. Block-level
    /// elements (headings, lists) get light handling via prefix detection.
    private func renderedMarkdown(_ markdown: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(paragraphs(in: markdown).enumerated()), id: \.offset) { _, block in
                block.view
            }
        }
    }

    private struct RenderedBlock {
        enum Kind { case heading(level: Int), bullet, paragraph }
        let kind: Kind
        let text: AttributedString

        @ViewBuilder var view: some View {
            switch kind {
            case .heading(let level):
                Text(text)
                    .font(.system(size: max(14, 22 - CGFloat(level * 2)), weight: .semibold))
                    .padding(.top, 6)
            case .bullet:
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(.secondary)
                    Text(text)
                }
            case .paragraph:
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func paragraphs(in markdown: String) -> [RenderedBlock] {
        var blocks: [RenderedBlock] = []
        var buffer: [String] = []

        func flushParagraph() {
            guard !buffer.isEmpty else { return }
            let text = buffer.joined(separator: " ")
            buffer.removeAll(keepingCapacity: true)
            if let attributed = try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                blocks.append(RenderedBlock(kind: .paragraph, text: attributed))
            } else {
                blocks.append(RenderedBlock(kind: .paragraph, text: AttributedString(text)))
            }
        }

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(heading)
                continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                let body = String(trimmed.dropFirst(2))
                let attributed = (try? AttributedString(
                    markdown: body,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                )) ?? AttributedString(body)
                blocks.append(RenderedBlock(kind: .bullet, text: attributed))
                continue
            }
            buffer.append(trimmed)
        }
        flushParagraph()
        return blocks
    }

    private func parseHeading(_ line: String) -> RenderedBlock? {
        var level = 0
        var rest = Substring(line)
        while rest.first == "#" { level += 1; rest = rest.dropFirst() }
        guard level > 0, level <= 6, rest.first?.isWhitespace == true else { return nil }
        let text = String(rest.trimmingCharacters(in: .whitespaces))
        let attributed = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        return RenderedBlock(kind: .heading(level: level), text: attributed)
    }

    // MARK: - File as note

    private func fileAsNote(_ answer: WikiAnswer) {
        let slug = slugify(answer.question)
        let path = "answers/\(slug).md"
        let date = Self.dateString(from: Date())
        let contents = """
        ---
        type: answer
        question: \(answer.question)
        asked: \(date)
        ---

        # \(answer.question)

        \(answer.markdown)
        """
        let op = WikiOperation(
            kind: .query,
            title: "File answer: \(answer.question)",
            rationale: "Filed from Query sheet.",
            changes: [.create(path: path, contents: contents)]
        )
        controller.dismissAnswer()
        controller.stage(op)
    }

    private func slugify(_ s: String) -> String {
        let lowered = s.lowercased()
        var chars: [Character] = []
        var lastWasDash = false
        for c in lowered {
            if c.isLetter || c.isNumber {
                chars.append(c)
                lastWasDash = false
            } else if !lastWasDash {
                chars.append("-")
                lastWasDash = true
            }
        }
        let raw = String(chars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return raw.isEmpty ? "answer" : String(raw.prefix(64))
    }

    private static func dateString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
