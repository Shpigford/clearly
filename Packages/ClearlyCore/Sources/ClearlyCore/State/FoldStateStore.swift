import Foundation
import CryptoKit

/// Identifies a fenced code block by the heading it lives under and its
/// position among siblings in that section. Survives unrelated edits to
/// the document. Breaks if the enclosing heading is renamed or if the
/// block's relative order under that heading changes — accepted tradeoffs.
public struct FoldKey: Codable, Hashable, Sendable {
    public let headingPath: [String]
    public let indexUnderHeading: Int

    public init(headingPath: [String], indexUnderHeading: Int) {
        self.headingPath = headingPath
        self.indexUnderHeading = indexUnderHeading
    }

    /// Stable, JSON-encoded string representation suitable for use as a
    /// dictionary key over the JS↔Swift bridge. JSON ordering is fixed by
    /// the encoder's keyEncodingStrategy default (alphabetical via
    /// JSONEncoder.OutputFormatting.sortedKeys).
    public var stableID: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    public init?(stableID: String) {
        guard let data = stableID.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        guard let key = try? decoder.decode(FoldKey.self, from: data) else { return nil }
        self = key
    }
}

/// Per-file fold state, keyed by file path. Backed by UserDefaults.
/// Entries are stored under "clearly.fold.<sha>" where <sha> is a stable
/// hash of the file path, so renames clear the state (acceptable).
public final class FoldStateStore: @unchecked Sendable {
    public static let shared = FoldStateStore(defaults: .standard)

    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.sabotage.clearly.foldstate", attributes: .concurrent)

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func folds(for fileURL: URL?) -> [FoldKey: Bool] {
        guard let key = Self.storageKey(for: fileURL) else { return [:] }
        return queue.sync {
            guard let data = defaults.data(forKey: key),
                  let raw = try? JSONDecoder().decode([String: Bool].self, from: data) else {
                return [:]
            }
            var result: [FoldKey: Bool] = [:]
            for (id, folded) in raw {
                if let foldKey = FoldKey(stableID: id) {
                    result[foldKey] = folded
                }
            }
            return result
        }
    }

    public func setFolded(_ folded: Bool, key: FoldKey, for fileURL: URL?) {
        guard let storageKey = Self.storageKey(for: fileURL) else { return }
        queue.async(flags: .barrier) {
            var raw: [String: Bool] = {
                guard let data = self.defaults.data(forKey: storageKey),
                      let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) else {
                    return [:]
                }
                return decoded
            }()
            if folded {
                raw[key.stableID] = true
            } else {
                raw.removeValue(forKey: key.stableID)
            }
            if raw.isEmpty {
                self.defaults.removeObject(forKey: storageKey)
            } else if let data = try? JSONEncoder().encode(raw) {
                self.defaults.set(data, forKey: storageKey)
            }
        }
    }

    /// Folded keys, encoded as their stableIDs. Convenient for sending
    /// over the JS bridge.
    public func foldedKeyIDs(for fileURL: URL?) -> [String] {
        folds(for: fileURL).filter { $0.value }.map { $0.key.stableID }
    }

    private static func storageKey(for fileURL: URL?) -> String? {
        guard let url = fileURL else { return nil }
        let path = url.standardizedFileURL.path
        guard !path.isEmpty else { return nil }
        return "clearly.fold." + Self.shortHash(path)
    }

    private static func shortHash(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
