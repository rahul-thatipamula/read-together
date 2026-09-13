import Foundation

/// Per-scope chat history + retrieval + generation.
final class ChatService {
    static let systemPrompt = """
    You are Read Together, a reading companion. The user reads books and often forgets earlier context.
    You are given (1) passages from the book(s) and (2) things the user asked before. Answer using ONLY that material.
    If the passages don't contain the answer, say so plainly and suggest where in the book to look.
    Be clear and concise. Cite pages like (p. 42). When answering across several books, name the book.
    """

    static let definePrompt = """
    You are a friendly dictionary for a reader. Give a short, clear definition of the word, then explain what it means in the book passage(s) provided, if any. Format:
    **word** — part of speech
    Definition in one or two sentences.
    In this book: how it is used here (cite the page).
    """

    private var stores: [String: JSONStore<[ChatMessage]>] = [:]
    let engine: LlamaEngine
    let library: LibraryService
    let memory: MemoryService
    let vocab: VocabService
    let stats: StatsService

    init(engine: LlamaEngine, library: LibraryService, memory: MemoryService, vocab: VocabService, stats: StatsService) {
        self.engine = engine; self.library = library; self.memory = memory; self.vocab = vocab; self.stats = stats
    }

    private func store(_ scope: Scope) -> JSONStore<[ChatMessage]> {
        if let s = stores[scope.key] { return s }
        let s = JSONStore<[ChatMessage]>(Paths.chats.appendingPathComponent("\(scope.key).json")) { [] }
        stores[scope.key] = s
        return s
    }

    func history(_ scope: Scope) -> [ChatMessage] { store(scope).read() }
    func clear(_ scope: Scope) { store(scope).write([]); memory.forget(scope: scope) }

    func recentQuestions(limit: Int = 30) -> [(scope: Scope, message: ChatMessage)] {
        var all: [(Scope, ChatMessage)] = []
        let scopes: [Scope] = [.library] + library.list().map { .book($0.id) }
        for s in scopes { for m in history(s) where m.role == .user { all.append((s, m)) } }
        return all.sorted { $0.1.createdAt > $1.1.createdAt }.prefix(limit).map { (scope: $0.0, message: $0.1) }
    }

    /// "define X", "meaning of X", "what does X mean", "what is X" → X
    static func parseDefine(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "[?.!]+$", with: "", options: .regularExpression)
        let patterns = [
            #"^/?define\s+"?([\p{L}\p{M}'-]+)"?$"#,
            #"^(?:what(?:'s| is) the )?meaning of\s+"?([\p{L}\p{M}'-]+)"?$"#,
            #"^what does\s+"?([\p{L}\p{M}'-]+)"?\s+mean$"#,
            #"^(?:what is|what's)\s+"?([\p{L}\p{M}'-]+)"?$"#,
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
               let r = Range(m.range(at: 1), in: t) {
                return String(t[r])
            }
        }
        return nil
    }

    /// Runs retrieval + generation. `selection` is optional text the user highlighted in the PDF.
    func send(scope: Scope, text: String, selection: String? = nil, modelId: String?,
              onPiece: @escaping @Sendable (String) -> Void) async throws -> ChatMessage {
        guard await engine.isLoaded else { throw LlamaEngine.EngineError.notLoaded }
        let s = store(scope)
        let prior = s.read()
        let books = library.list()
        func title(_ id: String) -> String { books.first { $0.id == id }?.title ?? "Unknown book" }
        let bookId = scope.bookId

        let shown = selection.map { "> \($0.prefix(400))\n\n\(text)" } ?? text
        s.update { $0.append(ChatMessage(id: UUID().uuidString, role: .user, content: shown, createdAt: Date())) }
        stats.countQuestion(bookId: bookId)

        let word = selection == nil ? Self.parseDefine(text) : nil
        var system = Self.systemPrompt
        var chunks: [ScoredChunk]
        var memories: [MemoryItem] = []
        if let word {
            system = Self.definePrompt
            chunks = bookId.map { library.findWord(bookId: $0, word: word) } ?? []
        } else {
            let query = selection.map { "\($0.prefix(300)) \(text)" } ?? text
            chunks = bookId.map { library.search(bookId: $0, query: query) } ?? library.searchAll(query: query)
            memories = memory.recall(query: text, scope: scope)
        }

        let isBook = bookId != nil
        let citations = chunks.map { Citation(page: $0.chunk.page, snippet: String($0.chunk.text.prefix(160)), bookId: $0.bookId, bookTitle: isBook ? nil : title($0.bookId)) }
        var passages = chunks.map { "[\(isBook ? "" : title($0.bookId) + ", ")Page \($0.chunk.page)]\n\($0.chunk.text)" }.joined(separator: "\n\n---\n\n")
        if chunks.isEmpty { passages = word != nil ? "(The word does not appear in the indexed text.)" : "(No passages found. The book may not be indexed yet.)" }

        let recalled = memories.isEmpty ? "" : "\n\nThings the user asked before:\n" + memories.map {
            let when = $0.createdAt.formatted(date: .abbreviated, time: .omitted)
            let whereStr = $0.bookTitle.map { " (\($0))" } ?? ""
            return "- On \(when)\(whereStr) they asked: \"\($0.question)\" — answer: \($0.answer.prefix(300))"
        }.joined(separator: "\n")

        var prompt: String
        if let word {
            prompt = "Word: \(word)\n\nPassages where it appears:\n\n\(passages)"
        } else if let selection {
            prompt = "The user selected this text in the book:\n\"\"\"\n\(selection)\n\"\"\"\n\nRelated passages:\n\n\(passages)\(recalled)\n\nRequest about the selection: \(text)"
        } else {
            prompt = "Passages:\n\n\(passages)\(recalled)\n\nQuestion: \(text)"
        }
        // Qwen3 thinks out loud unless told not to; keep answers snappy.
        if modelId?.hasPrefix("qwen3") == true { prompt += " /no_think" }

        var messages = [LlamaEngine.Message(role: "system", content: system)]
        for m in prior.suffix(6) { messages.append(.init(role: m.role == .user ? "user" : "assistant", content: m.content)) }
        messages.append(.init(role: "user", content: prompt))

        let raw = try await engine.generate(messages: messages, onPiece: onPiece)
        let content = Self.stripThinking(raw)

        let msg = ChatMessage(id: UUID().uuidString, role: .assistant, content: content, citations: citations, createdAt: Date())
        s.update { $0.append(msg) }

        if let word {
            vocab.add(word: word, definition: content, bookId: bookId, bookTitle: bookId.map(title), page: chunks.first?.chunk.page)
            stats.countWordLookup()
        } else {
            memory.remember(scope: scope, bookTitle: bookId.map(title), question: shown, answer: content)
        }
        return msg
    }

    static func stripThinking(_ s: String) -> String {
        s.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
