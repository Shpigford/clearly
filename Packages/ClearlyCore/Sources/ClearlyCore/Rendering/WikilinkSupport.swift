import Foundation

public enum WikilinkSupport {
    /// Private-use codepoint that the pre-cmark pass swaps in for any
    /// `|` (or `\|`) found inside a `[[...]]` wikilink. Hides the pipe
    /// from cmark-gfm's table parser so wikilinks survive intact inside
    /// table cells. The post-cmark pass either consumes it as the alias
    /// separator or restores it to a literal `|`.
    public static let pipeToken = "\u{E110}"

    /// Matches a complete wikilink after the pre-pass has run, so the
    /// alias separator is always `pipeToken` (never a literal pipe).
    /// Groups: 1 = target, 2 = optional heading after `#`, 3 = optional alias.
    public static let renderPattern: String = {
        let t = pipeToken
        // [[target(#heading)?(<token>alias)?]]
        return "\\[\\[([^\\]\\n#\(t)]+)(?:#([^\\]\\n\(t)]+))?(?:\(t)([^\\]\\n]+))?\\]\\]"
    }()
}
