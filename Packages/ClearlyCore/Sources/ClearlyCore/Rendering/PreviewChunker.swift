import Foundation

/// Splits a markdown document into render-friendly chunks for the lazy
/// preview pipeline. Splits only at safe boundaries (blank lines / ATX
/// headings) and refuses to split inside fenced code blocks so a chunk
/// boundary never lands between an opening and closing fence.
public enum PreviewChunker {
    public struct Chunk: Equatable, Sendable {
        public let markdown: String
        public let startLine: Int

        public init(markdown: String, startLine: Int) {
            self.markdown = markdown
            self.startLine = startLine
        }
    }

    public static func chunks(
        from markdown: String,
        targetCharacters: Int = 90_000,
        hardLimitCharacters: Int = 140_000
    ) -> [Chunk] {
        precondition(targetCharacters > 0, "targetCharacters must be positive")
        precondition(hardLimitCharacters >= targetCharacters, "hardLimit must be ≥ target")

        var chunks: [Chunk] = []
        var chunkStart = markdown.startIndex
        var currentStartLine = 1
        var currentLine = 1
        var currentCount = 0
        var lineStart = markdown.startIndex
        // Track whether the *next* line will start inside a fenced code
        // block. Toggled when we cross a ``` or ~~~ fence line.
        var insideFence = false

        while lineStart < markdown.endIndex {
            let lineEnd = markdown[lineStart...].firstIndex(of: "\n") ?? markdown.endIndex
            let nextLineStart = lineEnd < markdown.endIndex ? markdown.index(after: lineEnd) : markdown.endIndex
            if currentCount == 0 {
                chunkStart = lineStart
                currentStartLine = currentLine
            }
            currentCount += markdown.distance(from: lineStart, to: nextLineStart)

            let line = markdown[lineStart..<lineEnd]
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            let isFenceLine = trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
            if isFenceLine {
                insideFence.toggle()
            }

            // Safe boundary: ATX heading or blank line, *but* never split
            // while we're inside a fenced code block — a chunk boundary
            // there orphans the closing fence and breaks the renderer for
            // both halves.
            let isBlank = line.allSatisfy { $0 == " " || $0 == "\t" || $0 == "\r" }
            let isAtxHeading = line.first == "#"
            let canSplit = !insideFence && (isAtxHeading || isBlank)

            // Hard limit only kicks in when we're outside a fence; if we
            // hit the hard limit *inside* a fence, defer the split to the
            // next line that closes it so the chunk stays self-contained.
            let mustSplit = !insideFence && currentCount >= hardLimitCharacters
            if mustSplit || (currentCount >= targetCharacters && canSplit) {
                chunks.append(Chunk(
                    markdown: String(markdown[chunkStart..<nextLineStart]),
                    startLine: currentStartLine
                ))
                currentCount = 0
            }

            lineStart = nextLineStart
            currentLine += 1
        }

        if currentCount > 0 {
            chunks.append(Chunk(
                markdown: String(markdown[chunkStart..<markdown.endIndex]),
                startLine: currentStartLine
            ))
        }

        return chunks
    }
}
