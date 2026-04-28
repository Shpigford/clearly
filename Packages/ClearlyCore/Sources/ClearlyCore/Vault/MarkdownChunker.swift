import Foundation

/// Splits a markdown note into chunks suitable for embedding-based retrieval.
///
/// Strategy: heading-based primary split (H1/H2/H3 boundaries delimit sections), with a
/// token-based sliding-window fallback for any section that exceeds the chunk budget. Each
/// chunk's `embedText` is prepended with the document's title and heading path — Anthropic's
/// contextual-retrieval cookbook reports ~+35% recall from this trick over raw chunk bodies,
/// because the title gives a small mean-pooled embedder a stable topical anchor that bare
/// chunk text often loses.
///
/// Frontmatter is parsed for `title:` and used in the prefix when present; otherwise the
/// extension-stripped filename is used. Frontmatter itself is never embedded — high-entropy
/// YAML pollutes the embedding without adding retrieval signal.
///
/// Code blocks (``` fenced) are never split mid-fence: the line-by-line walk tracks fence
/// state and treats anything inside as opaque body.
public enum MarkdownChunker {

    public struct Chunk: Equatable {
        public let index: Int
        /// Verbatim chunk body. What the LLM sees in the context block.
        public let body: String
        /// Title- and heading-prefixed text. What the embedder sees.
        public let embedText: String
        /// UTF-8 byte offset of `body` into the original source string.
        public let textOffset: Int
        /// UTF-8 byte length of `body`.
        public let textLength: Int
        /// Heading nesting at the chunk's location, e.g. `["Local-First Software", "Core Principles"]`.
        public let headingPath: [String]

        public init(
            index: Int,
            body: String,
            embedText: String,
            textOffset: Int,
            textLength: Int,
            headingPath: [String]
        ) {
            self.index = index
            self.body = body
            self.embedText = embedText
            self.textOffset = textOffset
            self.textLength = textLength
            self.headingPath = headingPath
        }
    }

    /// Approximate target chunk size in whitespace-separated tokens. Tuned for small
    /// 384-dim embedders (e5-small, gte-small, bge-small) where retrieval quality
    /// degrades past ~256 tokens because the [CLS]/mean-pool representation has fixed
    /// capacity. Sentence-transformers community defaults converge on this number.
    public static let defaultTargetTokens = 256

    /// Sliding-window overlap (~15% of target) — enough that a sentence straddling a
    /// chunk boundary appears in both chunks, not enough to bloat the index.
    public static let defaultOverlapTokens = 40

    /// Chunk a markdown source string. Returns chunks in document order with stable
    /// `index` values so the storage layer's `(file_id, chunk_index)` PK is monotonic.
    public static func chunk(
        source: String,
        filename: String,
        targetTokens: Int = defaultTargetTokens,
        overlapTokens: Int = defaultOverlapTokens
    ) -> [Chunk] {
        guard !source.isEmpty else { return [] }

        let title = extractTitle(source: source, filename: filename)
        let (cleanBody, bodyOffsetInSource) = stripFrontmatter(source)
        let sections = splitIntoSections(body: cleanBody, bodyOffsetInSource: bodyOffsetInSource)
        if sections.isEmpty { return [] }

        var chunks: [Chunk] = []
        var nextIndex = 0
        for section in sections {
            let sectionChunks = chunkSection(
                section,
                title: title,
                targetTokens: targetTokens,
                overlapTokens: overlapTokens,
                startIndex: nextIndex
            )
            chunks.append(contentsOf: sectionChunks)
            nextIndex += sectionChunks.count
        }
        return chunks
    }

    // MARK: - Frontmatter

    /// Strip leading frontmatter; return (body, byteOffset of body into the original source).
    /// When there's no frontmatter, returns (source, 0).
    private static func stripFrontmatter(_ source: String) -> (String, Int) {
        guard let block = FrontmatterSupport.extract(from: source) else { return (source, 0) }
        let bodyOffset = source.utf8.count - block.body.utf8.count
        return (block.body, bodyOffset)
    }

    private static func extractTitle(source: String, filename: String) -> String {
        let extensionStripped = (filename as NSString).deletingPathExtension
        let fallback = extensionStripped.isEmpty ? filename : extensionStripped
        guard let block = FrontmatterSupport.extract(from: source),
              let titleField = block.fields.first(where: { $0.key.lowercased() == "title" }),
              !titleField.value.isEmpty
        else {
            return fallback
        }
        let cleaned = titleField.value
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? fallback : cleaned
    }

    // MARK: - Section walking

    /// One section between heading boundaries (or the entire body if no headings).
    private struct Section {
        let headingPath: [String]
        let body: String
        let bodyOffsetInSource: Int   // UTF-8 byte offset into the original source
    }

    /// Walk the body line-by-line, splitting at H1/H2/H3 boundaries. Tracks code-fence
    /// state so headings inside ``` fences don't trigger a split. Each emitted Section's
    /// `bodyOffsetInSource` is the absolute byte offset in the *original* source (frontmatter
    /// included), so the storage layer's `chunk_text_offset` lines up with raw file bytes.
    private static func splitIntoSections(body: String, bodyOffsetInSource: Int) -> [Section] {
        guard !body.isEmpty else { return [] }

        var sections: [Section] = []
        var currentH1: String? = nil
        var currentH2: String? = nil
        var currentH3: String? = nil
        var currentBody = ""
        var currentBodyStartOffset = bodyOffsetInSource
        var inCodeFence = false

        func flush() {
            let trimmed = currentBody.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                sections.append(Section(
                    headingPath: [currentH1, currentH2, currentH3].compactMap { $0 },
                    body: currentBody,
                    bodyOffsetInSource: currentBodyStartOffset
                ))
            }
            currentBody = ""
        }

        var byteCursor = bodyOffsetInSource
        let lines = body.components(separatedBy: "\n")
        for (lineIndex, line) in lines.enumerated() {
            let lineByteLength = line.utf8.count
            let trailingNewlineBytes = (lineIndex < lines.count - 1) ? 1 : 0

            let trimmedForFence = line.trimmingCharacters(in: .whitespaces)
            if trimmedForFence.hasPrefix("```") || trimmedForFence.hasPrefix("~~~") {
                inCodeFence.toggle()
                currentBody.append(line)
                if trailingNewlineBytes > 0 { currentBody.append("\n") }
                byteCursor += lineByteLength + trailingNewlineBytes
                continue
            }

            if !inCodeFence, let (level, title) = parseHeading(line) {
                if level <= 3 {
                    // H1/H2/H3 trigger a section split.
                    flush()
                    currentBodyStartOffset = byteCursor + lineByteLength + trailingNewlineBytes

                    switch level {
                    case 1:
                        currentH1 = title
                        currentH2 = nil
                        currentH3 = nil
                    case 2:
                        currentH2 = title
                        currentH3 = nil
                    default: // 3
                        currentH3 = title
                    }
                    byteCursor += lineByteLength + trailingNewlineBytes
                    continue
                }
                // H4+ stays inside the parent section. The chunker's job is to bound chunk
                // size, not to mirror every structural marker — finer-grained headings carry
                // less topical contrast and would balloon the chunk count for little recall
                // benefit.
                currentBody.append(line)
                if trailingNewlineBytes > 0 { currentBody.append("\n") }
                byteCursor += lineByteLength + trailingNewlineBytes
                continue
            }

            currentBody.append(line)
            if trailingNewlineBytes > 0 { currentBody.append("\n") }
            byteCursor += lineByteLength + trailingNewlineBytes
        }
        flush()

        return sections
    }

    private static func parseHeading(_ line: String) -> (Int, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        var level = 0
        var idx = trimmed.startIndex
        while idx < trimmed.endIndex, trimmed[idx] == "#" {
            level += 1
            idx = trimmed.index(after: idx)
        }
        guard level >= 1, level <= 6 else { return nil }
        guard idx < trimmed.endIndex, trimmed[idx].isWhitespace else { return nil }
        var title = String(trimmed[idx...]).trimmingCharacters(in: .whitespaces)
        while title.hasSuffix("#") {
            title = String(title.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return (level, title)
    }

    // MARK: - Chunk a section (with sliding-window fallback)

    private static func chunkSection(
        _ section: Section,
        title: String,
        targetTokens: Int,
        overlapTokens: Int,
        startIndex: Int
    ) -> [Chunk] {
        let trimmedBody = section.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return [] }

        // Locate the trimmed body's offset within the section body so byte offsets stay
        // accurate when leading whitespace is stripped.
        let leadingWhitespaceCount = section.body.prefix { $0.isWhitespace || $0.isNewline }.utf8.count
        let absOffset = section.bodyOffsetInSource + leadingWhitespaceCount

        let tokens = tokenize(trimmedBody)
        if tokens.count <= targetTokens {
            let embedText = buildEmbedText(title: title, headingPath: section.headingPath, body: trimmedBody)
            return [Chunk(
                index: startIndex,
                body: trimmedBody,
                embedText: embedText,
                textOffset: absOffset,
                textLength: trimmedBody.utf8.count,
                headingPath: section.headingPath
            )]
        }

        // Sliding window over the token stream. Each window emits a chunk whose body covers
        // the byte range from the first token's start to the last token's end.
        let bodyBytes = Array(trimmedBody.utf8)
        var chunks: [Chunk] = []
        var windowStart = 0
        let stride = max(1, targetTokens - overlapTokens)
        var nextIndex = startIndex

        while windowStart < tokens.count {
            let windowEnd = min(windowStart + targetTokens, tokens.count)
            let firstToken = tokens[windowStart]
            let lastToken = tokens[windowEnd - 1]
            let byteStart = firstToken.byteOffset
            let byteEnd = lastToken.byteOffset + lastToken.byteLength

            let slice = Array(bodyBytes[byteStart..<byteEnd])
            let windowBody = String(decoding: slice, as: UTF8.self)

            let embedText = buildEmbedText(title: title, headingPath: section.headingPath, body: windowBody)
            chunks.append(Chunk(
                index: nextIndex,
                body: windowBody,
                embedText: embedText,
                textOffset: absOffset + byteStart,
                textLength: byteEnd - byteStart,
                headingPath: section.headingPath
            ))
            nextIndex += 1

            if windowEnd >= tokens.count { break }
            windowStart += stride
        }

        return chunks
    }

    // MARK: - Embed-text composition

    /// Build the title- and heading-prefixed embed text. Mirrors the LlamaIndex / Anthropic
    /// contextual-retrieval pattern: "[Title] > [H1] > [H2]: <body>". Empty heading path
    /// degenerates to "[Title]: <body>". The prefix is stable across chunks of the same
    /// section so the embedder consistently anchors on the topical context.
    private static func buildEmbedText(title: String, headingPath: [String], body: String) -> String {
        var prefix = title
        for heading in headingPath {
            prefix += " > \(heading)"
        }
        return "\(prefix): \(body)"
    }

    // MARK: - Tokenization (chunk-boundary purposes only)

    private struct Token {
        let byteOffset: Int   // into the section body (trimmed)
        let byteLength: Int
    }

    /// Split the body into pseudo-tokens by whitespace runs. Used solely to bound chunk
    /// size; this does NOT need to match the embedder's WordPiece tokenization (the embedder
    /// does its own subword split internally). 1 whitespace-token ≈ 1.3 BERT subwords on
    /// English prose, so the 256-target_tokens bound stays comfortably under the embedder's
    /// 512-subword sequence cap.
    private static func tokenize(_ body: String) -> [Token] {
        var tokens: [Token] = []
        var byteOffset = 0
        var inToken = false
        var tokenStart = 0
        for byte in body.utf8 {
            let isSeparator = byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
            if isSeparator {
                if inToken {
                    tokens.append(Token(byteOffset: tokenStart, byteLength: byteOffset - tokenStart))
                    inToken = false
                }
            } else if !inToken {
                inToken = true
                tokenStart = byteOffset
            }
            byteOffset += 1
        }
        if inToken {
            tokens.append(Token(byteOffset: tokenStart, byteLength: byteOffset - tokenStart))
        }
        return tokens
    }
}
