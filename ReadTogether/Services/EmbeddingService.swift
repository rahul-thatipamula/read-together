import Foundation
import NaturalLanguage

/// Sentence embeddings from Apple's on-device NaturalLanguage framework.
/// No model download needed. Falls back to keyword overlap when unavailable.
final class EmbeddingService {
    private let embedding = NLEmbedding.sentenceEmbedding(for: .english)
    var isAvailable: Bool { embedding != nil }

    func embed(_ text: String) -> [Float] {
        guard let embedding else { return [] }
        // NLEmbedding works best on sentence-sized input; average over sentences for long chunks.
        let sentences = Self.sentences(in: text)
        var sum = [Double](repeating: 0, count: embedding.dimension)
        var n = 0
        for s in sentences {
            guard let v = embedding.vector(for: s) else { continue }
            for i in 0..<v.count { sum[i] += v[i] }
            n += 1
        }
        if n == 0, let v = embedding.vector(for: String(text.prefix(300))) { return v.map { Float($0) } }
        guard n > 0 else { return [] }
        return sum.map { Float($0 / Double(n)) }
    }

    static func sentences(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var out: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if s.count > 8 { out.append(String(s.prefix(400))) }
            return true
        }
        return out
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let d = na.squareRoot() * nb.squareRoot()
        return d == 0 ? 0 : dot / d
    }

    /// Cheap lexical score so search still works when embeddings are unavailable.
    static func keywordScore(query: String, text: String) -> Float {
        let q = Set(query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
        guard !q.isEmpty else { return 0 }
        let t = Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return Float(q.intersection(t).count) / Float(q.count)
    }
}
