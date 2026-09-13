import Foundation

/// Long-term memory of every Q&A, across books and sessions.
final class MemoryService {
    private let store = JSONStore<[MemoryItem]>(Paths.memory) { [] }
    private let embeddings: EmbeddingService
    init(embeddings: EmbeddingService) { self.embeddings = embeddings }

    func remember(scope: Scope, bookTitle: String?, question: String, answer: String) {
        let e = embeddings.embed("Q: \(question)\nA: \(answer.prefix(600))")
        store.update { $0.append(MemoryItem(id: UUID().uuidString, scope: scope.key, bookTitle: bookTitle, question: question, answer: answer, createdAt: Date(), embedding: e)) }
    }

    func recall(query: String, scope: Scope, k: Int = 3) -> [MemoryItem] {
        let q = embeddings.embed(query)
        return store.read()
            .map { m -> (MemoryItem, Float) in
                let sem = q.isEmpty || m.embedding.isEmpty ? 0 : EmbeddingService.cosine(q, m.embedding)
                let lex = EmbeddingService.keywordScore(query: query, text: m.question)
                return (m, sem * 0.8 + lex * 0.2 + (m.scope == scope.key ? 0.05 : 0))
            }
            .filter { $0.1 > 0.45 }
            .sorted { $0.1 > $1.1 }
            .prefix(k).map { $0.0 }
    }

    func forget(scope: Scope) { store.update { $0.removeAll { $0.scope == scope.key } } }
}
