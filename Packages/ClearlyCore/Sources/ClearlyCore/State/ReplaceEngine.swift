import Foundation

public enum ReplaceEngine {
    public static func substitution(for match: TextMatch, in text: String,
                                    template: String, isRegex: Bool) -> String {
        guard isRegex else { return template }
        let captures = captureStrings(for: match, in: text)
        return expandTemplate(template, captures: captures)
    }

    public static func applyAll(matches: [TextMatch], in text: String,
                                template: String, isRegex: Bool) -> String {
        guard !matches.isEmpty else { return text }
        let result = NSMutableString(string: text)
        for match in matches.reversed() {
            let replacement: String
            if isRegex {
                replacement = expandTemplate(template, captures: captureStrings(for: match, in: text))
            } else {
                replacement = template
            }
            result.replaceCharacters(in: match.range, with: replacement)
        }
        return result as String
    }

    private static func captureStrings(for match: TextMatch, in text: String) -> [String] {
        let nsText = text as NSString
        return match.captureRanges.map { range in
            guard range.location != NSNotFound else { return "" }
            return nsText.substring(with: range)
        }
    }

    /// Expand `$0`–`$9` and `\\`, `\$` escapes inside `template` using captured groups.
    /// Matches NSRegularExpression template semantics for the single-digit cases users
    /// will reach for in a find-bar replacement field.
    private static func expandTemplate(_ template: String, captures: [String]) -> String {
        var output = ""
        output.reserveCapacity(template.count)
        let chars = Array(template)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\\", i + 1 < chars.count {
                output.append(chars[i + 1])
                i += 2
                continue
            }
            if ch == "$", i + 1 < chars.count, let digit = chars[i + 1].wholeNumberValue, chars[i + 1].isASCII {
                if digit < captures.count {
                    output.append(captures[digit])
                }
                i += 2
                continue
            }
            output.append(ch)
            i += 1
        }
        return output
    }
}
