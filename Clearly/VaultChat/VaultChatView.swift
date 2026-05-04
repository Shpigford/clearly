import SwiftUI
import ClearlyCore

/// Trailing-edge panel that hosts vault chat. Message list up top, input
/// field at the bottom. Read-only RAG over the chat-bound vault — no filing,
/// no writes, just citations back to source notes via [[wiki-link]] so users
/// can jump from the answer to the underlying note.
struct VaultChatView: View {
    @Bindable var chat: VaultChatState
    let locations: [BookmarkedLocation]
    let send: (String) -> Void
    let openWikiLink: (String) -> Void

    @FocusState private var inputFocused: Bool
    @AppStorage("vaultChatPanelWidth") private var panelWidth: Double = 380
    @Environment(\.colorScheme) private var colorScheme

    private static let minPanelWidth: Double = 280
    private static let maxPanelWidth: Double = 700

    var body: some View {
        HStack(spacing: 0) {
            ResizeHandle(
                width: $panelWidth,
                minWidth: Self.minPanelWidth,
                maxWidth: Self.maxPanelWidth
            )
            VStack(alignment: .leading, spacing: 0) {
                header
                separator
                messages
                separator
                input
            }
        }
        .frame(width: max(Self.minPanelWidth, min(Self.maxPanelWidth, panelWidth)))
        .background(Theme.outlinePanelBackgroundSwiftUI)
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
        HStack(alignment: .center, spacing: 8) {
            Text("CHAT")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(1.5)
            vaultPicker
            Spacer()
            if !chat.messages.isEmpty {
                Button {
                    if let root = chat.vaultRoot {
                        chat.reset(vaultRoot: root)
                    } else {
                        chat.reset()
                    }
                    inputFocused = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New chat")
            }
            Button {
                chat.hide()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close chat")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var vaultPicker: some View {
        if locations.count > 1 {
            Menu {
                ForEach(locations) { location in
                    Button {
                        chat.pin(to: location.url)
                    } label: {
                        if let current = chat.vaultRoot, Self.sameURL(current, location.url) {
                            Label(location.name, systemImage: "checkmark")
                        } else {
                            Text(location.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(currentVaultName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Pick which vault to chat with")
        } else if !currentVaultName.isEmpty {
            Text(currentVaultName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var currentVaultName: String {
        guard let vaultURL = chat.vaultRoot else { return "" }
        if let match = locations.first(where: { Self.sameURL($0.url, vaultURL) }) {
            return match.name
        }
        return vaultURL.lastPathComponent
    }

    private static func sameURL(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.resolvingSymlinksInPath().path ==
            b.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(colorScheme == .dark ? Theme.separatorOpacityDark : Theme.separatorOpacity))
            .frame(height: 1)
            .padding(.horizontal, 12)
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
                            VaultChatBubble(message: message)
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
            Text("Ask this vault.")
                .font(.headline)
            Text("Read-only Q&A over your notes. Answers cite sources as `[[note-name]]`. Best results in English; tiny vaults will return thin context.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
    }

    // MARK: - Input

    private var input: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(inputPlaceholder, text: $chat.draft, axis: .vertical)
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

    private var inputPlaceholder: String {
        chat.messages.isEmpty ? "Ask a question…" : "Reply…"
    }

    private func submit() {
        let text = chat.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chat.isSending else { return }
        send(text)
    }

}

// MARK: - Bubble

private struct VaultChatBubble: View {
    let message: VaultChatMessage

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
        Text(message.role == .user ? "You" : "Clearly")
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

// MARK: - Resize handle

/// Thin draggable strip on the leading edge that resizes the chat panel.
/// Width persists across launches via `@AppStorage` on the parent view.
private struct ResizeHandle: View {
    @Binding var width: Double
    let minWidth: Double
    let maxWidth: Double
    @State private var startWidth: Double? = nil
    @State private var isHovered = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 5)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if startWidth == nil { startWidth = width }
                        let proposed = (startWidth ?? width) - Double(value.translation.width)
                        width = max(minWidth, min(maxWidth, proposed))
                    }
                    .onEnded { _ in startWidth = nil }
            )
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
