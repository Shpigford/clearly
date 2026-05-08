import Foundation

/// Names every formatting command the host menu can dispatch at the
/// active editor. Each case corresponds to a `ClearlyTextView` selector.
enum FormatCommand: String {
    case bold
    case italic
    case strikethrough
    case heading
    case link
    case image
    case bulletList
    case numberedList
    case todoList
    case blockquote
    case horizontalRule
    case table
    case inlineCode
    case codeBlock
    case inlineMath
    case mathBlock
    case pageBreak
}
