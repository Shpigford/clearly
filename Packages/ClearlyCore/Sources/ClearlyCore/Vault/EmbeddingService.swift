import Foundation
import NaturalLanguage

/// Computes contextual embeddings for vault notes using Apple's `NLContextualEmbedding`.
///
/// Vectors are mean-pooled subword token embeddings. The model is downloaded over-the-air the
/// first time `embed(_:)` is called; on a fresh install with no network the call throws and the
/// caller is expected to retry later (the indexer's catch-up sweep will pick the note back up).
public final class EmbeddingService {

    /// Bump to force a vault-wide re-embed. Stored next to each row so we can detect drift.
    /// v2 (2026-04-28): chunked embeddings — one row per chunk, embedText prefixed with
    ///                  filename + heading path. Schema migrated via `v3_chunked_embeddings`.
    public static let MODEL_VERSION: Int = 2

    /// Long inputs are truncated to the model's `maximumSequenceLength` token cap. We additionally
    /// cap input bytes here so very long notes don't make the call disproportionately slow.
    private static let maxCharacters = 8_000

    private let model: NLContextualEmbedding
    private var prepared = false
    private let prepareLock = NSLock()

    public init() throws {
        // TODO: multilingual model selection. English-only for now matches the wiki feature's
        // current target audience; bumping this to use `contextualEmbeddingsForValues` with a
        // script filter is a small change.
        guard let m = NLContextualEmbedding(language: .english) else {
            throw EmbeddingError.modelUnavailable
        }
        self.model = m
    }

    /// Returns the embedding dimensionality once the model is prepared. Pre-prepare returns 0.
    public var dimension: Int { model.dimension }

    /// Computes a single fixed-dim embedding via mean-pooling. Throws on empty / asset-missing /
    /// load failure. Safe to call from any thread; serializes preparation internally.
    public func embed(_ text: String) throws -> [Float] {
        let trimmed = text.count > Self.maxCharacters ? String(text.prefix(Self.maxCharacters)) : text
        guard !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EmbeddingError.emptyText
        }
        try prepareIfNeeded()

        let result = try model.embeddingResult(for: trimmed, language: .english)
        let dim = model.dimension
        guard dim > 0 else { throw EmbeddingError.modelUnavailable }

        var sum = [Double](repeating: 0, count: dim)
        var count = 0
        result.enumerateTokenVectors(in: trimmed.startIndex..<trimmed.endIndex) { vec, _ in
            // Defensive: model can in principle return a vector of unexpected length on malformed
            // input — guard so we never index past the buffer.
            let n = min(vec.count, dim)
            for i in 0..<n { sum[i] += vec[i] }
            count += 1
            return true
        }
        guard count > 0 else { throw EmbeddingError.emptyText }
        return sum.map { Float($0 / Double(count)) }
    }

    /// Cosine similarity. Returns 0 for zero-length vectors instead of NaN.
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        precondition(a.count == b.count, "cosine: vectors must share dimension")
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom > 0 ? dot / denom : 0
    }

    private func prepareIfNeeded() throws {
        prepareLock.lock()
        defer { prepareLock.unlock() }
        guard !prepared else { return }

        if !model.hasAvailableAssets {
            // Model assets aren't local yet — block this thread until the OS reports a result.
            // The indexer calls `embed` on a `.utility` background queue so blocking here is safe.
            let semaphore = DispatchSemaphore(value: 0)
            var resolution: NLContextualEmbedding.AssetsResult = .notAvailable
            var resolutionError: Error?
            model.requestAssets { result, error in
                resolution = result
                resolutionError = error
                semaphore.signal()
            }
            semaphore.wait()
            if let err = resolutionError { throw err }
            guard resolution == .available else { throw EmbeddingError.assetsUnavailable }
        }
        try model.load()
        prepared = true
    }
}

public enum EmbeddingError: Error, Equatable {
    case modelUnavailable
    case assetsUnavailable
    case emptyText
}

// MARK: - Storage helpers

extension Array where Element == Float {
    /// Round-trippable byte representation for persisting in a SQLite BLOB column.
    public var blobData: Data {
        withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Reconstructs a `[Float]` from its `blobData` representation. Returns `nil` if the byte
    /// count isn't a multiple of `MemoryLayout<Float>.size`.
    public static func fromBlobData(_ data: Data) -> [Float]? {
        let stride = MemoryLayout<Float>.size
        guard data.count % stride == 0 else { return nil }
        let count = data.count / stride
        return data.withUnsafeBytes { raw -> [Float] in
            let buf = raw.bindMemory(to: Float.self)
            return Array(UnsafeBufferPointer(start: buf.baseAddress, count: count))
        }
    }
}
