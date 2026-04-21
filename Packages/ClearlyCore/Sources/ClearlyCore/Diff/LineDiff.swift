import Foundation

public enum LineDiff {
    public enum Op: Sendable { case same, added, removed }

    public struct Row: Sendable, Identifiable {
        public let id: Int
        public let op: Op
        public let left: String?
        public let right: String?

        public init(id: Int, op: Op, left: String?, right: String?) {
            self.id = id
            self.op = op
            self.left = left
            self.right = right
        }
    }

    public enum DiffError: Error { case tooLarge }

    public static let maxLines = 10_000

    /// Aligns `left` and `right` line-by-line using `CollectionDifference`.
    /// Throws `DiffError.tooLarge` when either side exceeds `maxLines` — the
    /// diff cost (O(n·d)) degrades too fast to render synchronously beyond
    /// that.
    public static func rows(left: String, right: String) throws -> [Row] {
        let leftLines = left.components(separatedBy: "\n")
        let rightLines = right.components(separatedBy: "\n")
        if leftLines.count > maxLines || rightLines.count > maxLines {
            throw DiffError.tooLarge
        }

        let diff = rightLines.difference(from: leftLines)
        var removedAt = Set<Int>()
        var insertedAt = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removedAt.insert(offset)
            case .insert(let offset, _, _): insertedAt.insert(offset)
            }
        }

        var rows: [Row] = []
        var i = 0, j = 0
        var rowID = 0
        while i < leftLines.count || j < rightLines.count {
            let leftIsRemoved = i < leftLines.count && removedAt.contains(i)
            let rightIsInserted = j < rightLines.count && insertedAt.contains(j)

            if leftIsRemoved && rightIsInserted {
                rows.append(Row(id: rowID, op: .removed, left: leftLines[i], right: nil))
                rowID += 1
                rows.append(Row(id: rowID, op: .added, left: nil, right: rightLines[j]))
                rowID += 1
                i += 1; j += 1
            } else if leftIsRemoved {
                rows.append(Row(id: rowID, op: .removed, left: leftLines[i], right: nil))
                rowID += 1
                i += 1
            } else if rightIsInserted {
                rows.append(Row(id: rowID, op: .added, left: nil, right: rightLines[j]))
                rowID += 1
                j += 1
            } else if i < leftLines.count && j < rightLines.count {
                rows.append(Row(id: rowID, op: .same, left: leftLines[i], right: rightLines[j]))
                rowID += 1
                i += 1; j += 1
            } else if i < leftLines.count {
                rows.append(Row(id: rowID, op: .removed, left: leftLines[i], right: nil))
                rowID += 1
                i += 1
            } else if j < rightLines.count {
                rows.append(Row(id: rowID, op: .added, left: nil, right: rightLines[j]))
                rowID += 1
                j += 1
            } else {
                break
            }
        }
        return rows
    }
}
