/// Recognizes the editable marker and separator at the start of an ATX
/// heading. The heading content may still be empty while the user is typing.
public enum ATXHeadingPrefix {
    public static func parse(in line: String) -> Substring? {
        var index = line.startIndex
        var level = 0

        while index < line.endIndex, line[index] == "#" {
            level += 1
            guard level <= 6 else { return nil }
            index = line.index(after: index)
        }

        guard level > 0, index < line.endIndex,
              line[index] == " " || line[index] == "\t" else {
            return nil
        }

        repeat {
            index = line.index(after: index)
        } while index < line.endIndex
            && (line[index] == " " || line[index] == "\t")

        return line[..<index]
    }
}
