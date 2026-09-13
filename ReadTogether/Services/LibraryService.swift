import Foundation
import PDFKit

/// Books on disk + per-book vector index (JSON of chunks). Cosine search in memory.
final class LibraryService {
    private let store = JSONStore<[Book]>(Paths.library) { [] }
    private var indexCache: [String: [Chunk]] = [:]
    private let embeddings: EmbeddingService

    init(embeddings: EmbeddingService) { self.embeddings = embeddings }

    func list() -> [Book] { store.read() }
    func get(_ id: String) -> Book? { list().first { $0.id == id } }
    func fileURL(_ book: Book) -> URL { Paths.books.appendingPathComponent("\(book.id).pdf") }

    func importPDF(from source: URL) throws -> Book {
        let id = UUID().uuidString
        let dest = Paths.books.appendingPathComponent("\(id).pdf")
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: source, to: dest)
        let doc = PDFDocument(url: dest)
        let title = doc?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        let book = Book(
            id: id,
            title: (title?.isEmpty == false ? title! : source.deletingPathExtension().lastPathComponent),
            fileName: source.lastPathComponent,
            pageCount: doc?.pageCount ?? 0,
            addedAt: Date(), indexed: false, lastPage: 1)
        store.update { $0.insert(book, at: 0) }
        return book
    }

    func update(_ id: String, _ fn: (inout Book) -> Void) {
        store.update { books in
            if let i = books.firstIndex(where: { $0.id == id }) { fn(&books[i]) }
        }
    }

    func remove(_ id: String) {
        if let b = get(id) { try? FileManager.default.removeItem(at: fileURL(b)) }
        store.update { $0.removeAll { $0.id == id } }
        indexCache[id] = nil
        try? FileManager.default.removeItem(at: indexURL(id))
        try? FileManager.default.removeItem(at: Paths.chats.appendingPathComponent("\(id).json"))
    }

    private func indexURL(_ id: String) -> URL { Paths.indexes.appendingPathComponent("\(id).json") }

    /// Split page text into ~220-word chunks with 40-word overlap, keeping page numbers.
    static func chunk(pages: [(page: Int, text: String)], words: Int = 220, overlap: Int = 40) -> [(page: Int, text: String)] {
        var out: [(Int, String)] = []
        for (page, text) in pages {
            let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard tokens.count >= 20 else { continue }
            var i = 0
            while i < tokens.count {
                out.append((page, tokens[i..<min(i + words, tokens.count)].joined(separator: " ")))
                if i + words >= tokens.count { break }
                i += words - overlap
            }
        }
        return out
    }

    /// Extract text with PDFKit and embed every chunk. Reports progress 0...1.
    func index(_ book: Book, progress: @escaping (Double) -> Void) throws {
        guard let doc = PDFDocument(url: fileURL(book)) else { throw NSError(domain: "ReadTogether", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not open PDF"]) }
        var pages: [(page: Int, text: String)] = []
        for i in 0..<doc.pageCount {
            pages.append((i + 1, doc.page(at: i)?.string ?? ""))
        }
        let chunks = Self.chunk(pages: pages)
        var result: [Chunk] = []
        for (i, c) in chunks.enumerated() {
            result.append(Chunk(id: UUID().uuidString, page: c.page, text: c.text, embedding: embeddings.embed(c.text)))
            if i % 5 == 0 { progress(Double(i + 1) / Double(max(1, chunks.count))) }
        }
        let data = try JSONEncoder().encode(result)
        try data.write(to: indexURL(book.id), options: .atomic)
        indexCache[book.id] = result
        update(book.id) { $0.indexed = true }
        progress(1)
    }

    private func loadIndex(_ id: String) -> [Chunk] {
        if let c = indexCache[id] { return c }
        guard let data = try? Data(contentsOf: indexURL(id)), let chunks = try? JSONDecoder().decode([Chunk].self, from: data) else { return [] }
        indexCache[id] = chunks
        return chunks
    }

    private func score(query: String, q: [Float], chunk: Chunk) -> Float {
        let sem = q.isEmpty || chunk.embedding.isEmpty ? 0 : EmbeddingService.cosine(q, chunk.embedding)
        let lex = EmbeddingService.keywordScore(query: query, text: chunk.text)
        return sem * 0.8 + lex * 0.2
    }

    func search(bookId: String, query: String, k: Int = 6) -> [ScoredChunk] {
        let q = embeddings.embed(query)
        return loadIndex(bookId)
            .map { ScoredChunk(chunk: $0, bookId: bookId, score: score(query: query, q: q, chunk: $0)) }
            .sorted { $0.score > $1.score }
            .prefix(k).map { $0 }
    }

    func searchAll(query: String, k: Int = 8) -> [ScoredChunk] {
        let q = embeddings.embed(query)
        var all: [ScoredChunk] = []
        for b in list() where b.indexed {
            for c in loadIndex(b.id) { all.append(ScoredChunk(chunk: c, bookId: b.id, score: score(query: query, q: q, chunk: c))) }
        }
        return all.sorted { $0.score > $1.score }.prefix(k).map { $0 }
    }

    func findWord(bookId: String, word: String, k: Int = 4) -> [ScoredChunk] {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return loadIndex(bookId)
            .filter { re.firstMatch(in: $0.text, range: NSRange($0.text.startIndex..., in: $0.text)) != nil }
            .prefix(k).map { ScoredChunk(chunk: $0, bookId: bookId, score: 1) }
    }
}
