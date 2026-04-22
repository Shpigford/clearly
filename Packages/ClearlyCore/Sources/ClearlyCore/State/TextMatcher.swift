import Foundation

public enum TextMatcher {
    public static func ranges(of query: String, in text: String, caseSensitive: Bool = false) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let nsText = text as NSString
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: nsText.length)
        let options: NSString.CompareOptions = caseSensitive ? [] : .caseInsensitive
        while searchRange.location < nsText.length {
            let found = nsText.range(of: query, options: options, range: searchRange)
            if found.location == NSNotFound { break }
            ranges.append(found)
            searchRange.location = found.upperBound
            searchRange.length = nsText.length - searchRange.location
        }
        return ranges
    }
}
