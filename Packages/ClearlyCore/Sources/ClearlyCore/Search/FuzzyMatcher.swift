import Foundation

public struct FuzzyMatchResult {
    public let score: Int
    public let matchedRanges: [Range<String.Index>]

    public init(score: Int, matchedRanges: [Range<String.Index>]) {
        self.score = score
        self.matchedRanges = matchedRanges
    }
}

public enum FuzzyMatcher {
    /// Sequential character matching with gap penalties and separator bonuses.
    /// Returns nil if not all query characters match.
    public static func match(query: String, target: String) -> FuzzyMatchResult? {
        let queryLower = query.lowercased()
        let targetLower = target.lowercased()

        guard !queryLower.isEmpty else { return FuzzyMatchResult(score: 0, matchedRanges: []) }

        var queryIndex = queryLower.startIndex
        var targetIndex = targetLower.startIndex
        var score = 0
        var matchedRanges: [Range<String.Index>] = []
        var consecutiveMatches = 0
        var lastMatchIndex: String.Index?

        let separators: Set<Character> = ["/", ".", "_", "-", " "]

        while queryIndex < queryLower.endIndex && targetIndex < targetLower.endIndex {
            if queryLower[queryIndex] == targetLower[targetIndex] {
                score += 10

                if let last = lastMatchIndex, targetLower.index(after: last) == targetIndex {
                    consecutiveMatches += 1
                    score += consecutiveMatches * 5
                } else {
                    consecutiveMatches = 0
                }

                if targetIndex == targetLower.startIndex {
                    score += 15
                } else {
                    let prevIndex = targetLower.index(before: targetIndex)
                    if separators.contains(targetLower[prevIndex]) {
                        score += 12
                    }
                    let origChar = target[target.index(target.startIndex, offsetBy: targetLower.distance(from: targetLower.startIndex, to: targetIndex))]
                    if origChar.isUppercase {
                        score += 8
                    }
                }

                let origTargetIndex = target.index(target.startIndex, offsetBy: targetLower.distance(from: targetLower.startIndex, to: targetIndex))
                let nextOrigIndex = target.index(after: origTargetIndex)
                if let last = matchedRanges.last, last.upperBound == origTargetIndex {
                    matchedRanges[matchedRanges.count - 1] = last.lowerBound..<nextOrigIndex
                } else {
                    matchedRanges.append(origTargetIndex..<nextOrigIndex)
                }

                lastMatchIndex = targetIndex
                queryIndex = queryLower.index(after: queryIndex)
            } else {
                if lastMatchIndex != nil {
                    score -= 1
                }
            }
            targetIndex = targetLower.index(after: targetIndex)
        }

        guard queryIndex == queryLower.endIndex else { return nil }

        let lengthDiff = target.count - query.count
        score -= lengthDiff

        return FuzzyMatchResult(score: max(0, score), matchedRanges: matchedRanges)
    }
}
