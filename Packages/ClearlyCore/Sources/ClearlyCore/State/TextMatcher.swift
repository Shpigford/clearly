import Foundation

public struct TextMatch: Equatable, Sendable {
    public let range: NSRange
    public let captureRanges: [NSRange]

    public init(range: NSRange, captureRanges: [NSRange] = []) {
        self.range = range
        self.captureRanges = captureRanges
    }
}

public struct TextMatchOptions: Equatable, Sendable {
    public var caseSensitive: Bool
    public var wholeWord: Bool
    public var useRegex: Bool

    public init(caseSensitive: Bool = false, wholeWord: Bool = false, useRegex: Bool = false) {
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
        self.useRegex = useRegex
    }
}

public enum TextMatcherError: Error, Equatable {
    case invalidRegex(String)
}

public enum TextMatcher {
    public static func matches(of query: String, in text: String,
                               options: TextMatchOptions = TextMatchOptions()) throws -> [TextMatch] {
        guard !query.isEmpty else { return [] }

        let pattern: String
        if options.useRegex {
            pattern = options.wholeWord ? "\\b(?:\(query))\\b" : query
        } else {
            let escaped = NSRegularExpression.escapedPattern(for: query)
            pattern = options.wholeWord ? "\\b\(escaped)\\b" : escaped
        }

        var regexOptions: NSRegularExpression.Options = []
        if !options.caseSensitive { regexOptions.insert(.caseInsensitive) }

        let regex: NSRegularExpression
        do {
            regex = try compiledRegex(pattern: pattern, options: regexOptions)
        } catch {
            throw TextMatcherError.invalidRegex(error.localizedDescription)
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var results: [TextMatch] = []
        regex.enumerateMatches(in: text, options: [], range: fullRange) { result, _, _ in
            guard let result = result, result.range.location != NSNotFound, result.range.length > 0 else { return }
            var captures: [NSRange] = []
            captures.reserveCapacity(result.numberOfRanges)
            for i in 0..<result.numberOfRanges {
                captures.append(result.range(at: i))
            }
            results.append(TextMatch(range: result.range, captureRanges: captures))
        }
        return results
    }

    public static func ranges(of query: String, in text: String, caseSensitive: Bool = false) -> [NSRange] {
        let opts = TextMatchOptions(caseSensitive: caseSensitive, wholeWord: false, useRegex: false)
        return (try? matches(of: query, in: text, options: opts).map(\.range)) ?? []
    }

    private struct RegexCacheKey: Hashable {
        let pattern: String
        let options: UInt
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var regexCache: [RegexCacheKey: NSRegularExpression] = [:]
    private static let cacheLimit = 32

    private static func compiledRegex(pattern: String, options: NSRegularExpression.Options) throws -> NSRegularExpression {
        let key = RegexCacheKey(pattern: pattern, options: options.rawValue)
        cacheLock.lock()
        if let cached = regexCache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let regex = try NSRegularExpression(pattern: pattern, options: options)

        cacheLock.lock()
        if regexCache.count >= cacheLimit { regexCache.removeAll(keepingCapacity: true) }
        regexCache[key] = regex
        cacheLock.unlock()
        return regex
    }
}
