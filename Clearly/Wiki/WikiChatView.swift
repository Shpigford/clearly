import SwiftUI
import ClearlyCore

/// Trailing-edge panel that hosts the Wiki chat. Message list up top, input
/// field at the bottom. Each assistant turn has a "File as Note" action that
/// stages a normal WikiOperation through the diff-review pipeline, so the
/// vault still grows via explicit filing (Karpathy's premise) rather than
/// accumulating ephemeral chat.
struct WikiChatView: View {
    @Bindable var chat: WikiChatState
    @Bindable var controller: WikiOperationController
    let vaultRoot: URL?
    let send: (String) -> Void
    let openWikiLink: (String) -> Void

    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messages
            Divider()
            input
        }
        .frame(minWidth: 320, idealWidth: 380, maxWidth: 480)
        .background(Theme.backgroundColorSwiftUI)
        .environment(\.openURL, OpenURLAction { url in
            // `clearly-wiki://<target>` is our synthesized scheme for
            // [[wiki-links]]. Anything else (http, mailto…) falls through
            // to the system handler.
            if url.scheme == WikiLinkURL.scheme,
               let target = WikiLinkURL.target(from: url) {
                openWikiLink(target)
                return .handled
            }
            return .systemAction
        })
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .foregroundStyle(.secondary)
            Text("Wiki Chat")
                .font(.headline)
            Spacer()
            if !chat.messages.isEmpty {
                Button {
                    chat.reset()
                    inputFocused = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .help("Start a new conversation")
            }
            Button {
                chat.hide()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close chat")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Messages

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if chat.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(chat.messages) { message in
                            WikiChatBubble(
                                message: message,
                                onFileAsNote: { fileAsNote(message) }
                            )
                            .id(message.id)
                        }
                    }
                    if chat.isSending {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 4)
                    }
                    if let error = chat.sendError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .onChange(of: chat.messages.count) { _, _ in
                if let last = chat.messages.last {
                    withAnimation(Theme.Motion.smooth) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ask the wiki.")
                .font(.headline)
            Text("Claude reads your notes, answers with citations, and leaves the filing to you. \"File as Note\" on any answer saves it to `answers/`.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
    }

    // MARK: - Input

    private var input: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask a question…", text: $chat.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit {
                    submit()
                }

            Button {
                submit()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        canSend
                            ? Theme.accentColorSwiftUI
                            : Color.secondary.opacity(0.5)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help("Send (⏎)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear { inputFocused = true }
    }

    private var canSend: Bool {
        !chat.isSending && !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let text = chat.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chat.isSending else { return }
        send(text)
    }

    // MARK: - File as note

    private func fileAsNote(_ message: WikiChatMessage) {
        guard message.role == .assistant else { return }
        let precedingUser = precedingUserMessage(for: message)?.text ?? "chat answer"
        let slug = slugify(precedingUser)
        let date = Self.dateString(from: message.timestamp)
        let contents = """
        ---
        type: answer
        question: \(precedingUser)
        asked: \(date)
        ---

        # \(precedingUser)

        \(message.text)
        """
        let op = WikiOperation(
            kind: .query,
            title: "File answer: \(precedingUser)",
            rationale: "Filed from Wiki Chat.",
            changes: [.create(path: "answers/\(slug).md", contents: contents)]
        )
        controller.stage(op)
    }

    private func precedingUserMessage(for message: WikiChatMessage) -> WikiChatMessage? {
        guard let idx = chat.messages.firstIndex(where: { $0.id == message.id }) else { return nil }
        for i in stride(from: idx - 1, through: 0, by: -1) where chat.messages[i].role == .user {
            return chat.messages[i]
        }
        return nil
    }

    private func slugify(_ s: String) -> String {
        let lowered = s.lowercased()
        var chars: [Character] = []
        var lastDash = false
        for c in lowered {
            if c.isLetter || c.isNumber {
                chars.append(c); lastDash = false
            } else if !lastDash {
                chars.append("-"); lastDash = true
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

// MARK: - Bubble

private struct WikiChatBubble: View {
    let message: WikiChatMessage
    let onFileAsNote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            roleLabel
            bubbleBody
            if message.role == .assistant {
                actionRow
            }
        }
    }

    private var roleLabel: some View {
        Text(message.role == .user ? "You" : "Wiki")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    @ViewBuilder
    private var bubbleBody: some View {
        switch message.role {
        case .user:
            Text(message.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .assistant:
            MarkdownBlockView(markdown: message.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                onFileAsNote()
            } label: {
                Label("File as Note", systemImage: "square.and.arrow.down")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(message.text, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

// MARK: - Wiki-link URL scheme

enum WikiLinkURL {
    static let scheme = "clearly-wiki"

    /// Convert `[[target]]` and `[[target|display]]` patterns into standard
    /// markdown links with our synthesized `clearly-wiki://` scheme so
    /// AttributedString(markdown:) renders them as tappable links. The view's
    /// environment `openURL` handler intercepts the scheme and routes to
    /// `openWikiLink`.
    static func preprocess(_ markdown: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"\[\[([^\]|\n]+?)(?:\|([^\]\n]+?))?\]\]"#
        ) else { return markdown }

        let ns = markdown as NSString
        var result = ""
        var cursor = 0
        let range = NSRange(location: 0, length: ns.length)
        for match in regex.matches(in: markdown, range: range) {
            let prefixRange = NSRange(location: cursor, length: match.range.location - cursor)
            result.append(ns.substring(with: prefixRange))

            let target = ns.substring(with: match.range(at: 1))
            let displayRange = match.range(at: 2)
            let display = displayRange.location != NSNotFound
                ? ns.substring(with: displayRange)
                : target

            let escapedTarget = target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target
            result.append("[\(display)](\(scheme)://\(escapedTarget))")
            cursor = match.range.location + match.range.length
        }
        result.append(ns.substring(from: cursor))
        return result
    }

    static func target(from url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        // URL parses `clearly-wiki://people/josh-pigford` as host=people,
        // path=/josh-pigford. Reassemble them.
        let host = url.host ?? ""
        let path = url.path
        let combined = path.isEmpty ? host : "\(host)\(path)"
        return combined.removingPercentEncoding ?? combined
    }
}

// MARK: - Markdown renderer

/// Lightweight markdown block renderer used for assistant messages. Handles
/// headings, bullet lists, and inline formatting (bold, italic, code, links)
/// via AttributedString markdown. Code fences and tables fall back to plain
/// text in monospaced font. Good enough for chat; full rendering stays in
/// the main preview after "File as Note".
struct MarkdownBlockView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                block.view
            }
        }
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        var codeFence: [String]? = nil

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let joined = paragraph.joined(separator: " ")
            paragraph.removeAll(keepingCapacity: true)
            let prepared = WikiLinkURL.preprocess(joined)
            let attributed = (try? AttributedString(
                markdown: prepared,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
            )) ?? AttributedString(joined)
            result.append(.paragraph(attributed))
        }

        for line in markdown.components(separatedBy: "\n") {
            if codeFence != nil {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    let body = codeFence?.joined(separator: "\n") ?? ""
                    result.append(.code(body))
                    codeFence = nil
                } else {
                    codeFence?.append(line)
                }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flushParagraph()
                codeFence = []
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if let heading = parseHeading(trimmed) {
                flushParagraph()
                result.append(heading)
                continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                let body = String(trimmed.dropFirst(2))
                let prepared = WikiLinkURL.preprocess(body)
                let attributed = (try? AttributedString(
                    markdown: prepared,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
                )) ?? AttributedString(body)
                result.append(.bullet(attributed))
                continue
            }
            paragraph.append(trimmed)
        }
        flushParagraph()
        if let remaining = codeFence {
            result.append(.code(remaining.joined(separator: "\n")))
        }
        return result
    }

    private func parseHeading(_ line: String) -> Block? {
        var level = 0
        var rest = Substring(line)
        while rest.first == "#" { level += 1; rest = rest.dropFirst() }
        guard level > 0, level <= 6, rest.first?.isWhitespace == true else { return nil }
        let text = String(rest.trimmingCharacters(in: .whitespaces))
        let prepared = WikiLinkURL.preprocess(text)
        let attributed = (try? AttributedString(
            markdown: prepared,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        )) ?? AttributedString(text)
        return .heading(level: level, text: attributed)
    }

    private enum Block {
        case paragraph(AttributedString)
        case heading(level: Int, text: AttributedString)
        case bullet(AttributedString)
        case code(String)

        @ViewBuilder var view: some View {
            switch self {
            case .paragraph(let text):
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            case .heading(let level, let text):
                Text(text)
                    .font(.system(size: max(13, 20 - CGFloat(level * 2)), weight: .semibold))
            case .bullet(let text):
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(.secondary)
                    Text(text)
                }
            case .code(let body):
                Text(body)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(6)
            }
        }
    }
}
