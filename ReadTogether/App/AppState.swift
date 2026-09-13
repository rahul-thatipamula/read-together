import SwiftUI
import Combine
import PDFKit

enum SidebarItem: Hashable {
    case library, ask, reading, models
    case book(String)
}

/// Text the user selected in the PDF, ready to highlight / copy / ask about.
struct PDFSelectionInfo: Equatable {
    var text: String
    var pageIndex: Int
    var rects: [CGRect]        // page space, per line
    var anchor: CGPoint        // view space, where to show the floating bar
}

@MainActor
final class AppState: ObservableObject {
    // services
    let embeddings = EmbeddingService()
    let engine = LlamaEngine()
    let models = ModelService()
    let library: LibraryService
    let memory: MemoryService
    let vocab: VocabService
    let marks: MarksService
    let stats: StatsService
    let chat: ChatService

    // navigation
    @Published var selection: SidebarItem? = .library
    @Published var focusMode = false
    @Published var chatOpen = true
    @Published var showMarks = false

    // library
    @Published var books: [Book] = []
    @Published var indexing: [String: Double] = [:]
    @Published var bookMarks: [Mark] = []

    // engine
    @Published var engineState: EngineState = .idle
    @Published var loadedModelId: String?
    @AppStorage("preferredModel") var preferredModelId: String = ""

    // chat
    @Published var chatScope: Scope = .library
    @Published var messages: [ChatMessage] = []
    @Published var streaming: String?
    @Published var chatError: String?
    @Published var jumpToPage: Int?                       // reader listens and scrolls

    // stats
    @Published var statsSummary: StatsSummary?
    @Published var vocabulary: [VocabEntry] = []
    @Published var recentQuestions: [(scope: Scope, message: ChatMessage)] = []

    private var heartbeat: Timer?

    var activeBook: Book? {
        if case .book(let id) = selection { return books.first { $0.id == id } }
        return nil
    }

    init() {
        library = LibraryService(embeddings: embeddings)
        memory = MemoryService(embeddings: embeddings)
        vocab = VocabService()
        marks = MarksService()
        stats = StatsService()
        chat = ChatService(engine: engine, library: library, memory: memory, vocab: vocab, stats: stats)
        books = library.list()
        startHeartbeat()
        if !preferredModelId.isEmpty, models.installed.contains(preferredModelId) {
            Task { try? await loadModel(preferredModelId) }
        }
    }

    // MARK: engine

    func loadModel(_ id: String) async throws {
        guard let path = models.path(for: id) else { throw LlamaEngine.EngineError.loadFailed("Model is not installed") }
        preferredModelId = id
        engineState = .loading
        do {
            try await engine.load(modelId: id, path: path)
            loadedModelId = id
            engineState = .ready
        } catch {
            engineState = .error(error.localizedDescription)
            throw error
        }
    }

    func unloadModel() async {
        await engine.unload()
        loadedModelId = nil
        engineState = .idle
    }

    func shutdown() async {
        models.cancelAll()
        await engine.unload()
    }

    // MARK: library

    func refreshBooks() { books = library.list() }

    func importPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.message = "Add books"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let b = try? library.importPDF(from: url) { books.insert(b, at: 0) }
        }
    }

    func open(_ book: Book) {
        selection = .book(book.id)
        bookMarks = marks.marks(for: book.id)
        setScope(.book(book.id))
    }

    func remove(_ book: Book) {
        library.remove(book.id)
        marks.removeAll(bookId: book.id)
        books.removeAll { $0.id == book.id }
        if case .book(book.id) = selection { selection = .library }
    }

    func setLastPage(_ book: Book, _ page: Int) {
        guard page != book.lastPage else { return }
        library.update(book.id) { $0.lastPage = page }
        if let i = books.firstIndex(where: { $0.id == book.id }) { books[i].lastPage = page }
    }

    func indexBook(_ book: Book) {
        guard indexing[book.id] == nil else { return }
        indexing[book.id] = 0
        Task.detached { [library] in
            do {
                try library.index(book) { p in Task { @MainActor in self.indexing[book.id] = p } }
                await MainActor.run {
                    self.indexing[book.id] = nil
                    self.refreshBooks()
                }
            } catch {
                await MainActor.run { self.indexing[book.id] = nil; self.chatError = error.localizedDescription }
            }
        }
    }

    // MARK: marks

    func addMark(from sel: PDFSelectionInfo, book: Book, color: MarkColor) {
        let m = Mark(id: UUID().uuidString, bookId: book.id, pageIndex: sel.pageIndex, text: sel.text, rects: sel.rects, color: color, note: nil, createdAt: Date())
        marks.add(m)
        bookMarks = marks.marks(for: book.id)
    }

    func removeMark(_ id: String) {
        marks.remove(id)
        if let b = activeBook { bookMarks = marks.marks(for: b.id) }
    }

    // MARK: chat

    func setScope(_ scope: Scope) {
        if chatScope == scope, !messages.isEmpty { return }
        chatScope = scope
        streaming = nil
        chatError = nil
        messages = chat.history(scope)
    }

    func send(_ text: String, selection: PDFSelectionInfo? = nil) {
        guard streaming == nil, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let scope = chatScope
        let shown = selection.map { "> \($0.text.prefix(400))\n\n\(text)" } ?? text
        messages.append(ChatMessage(id: UUID().uuidString, role: .user, content: shown, createdAt: Date()))
        streaming = ""
        chatError = nil
        engineState = .generating
        let modelId = loadedModelId
        Task {
            do {
                let msg = try await chat.send(scope: scope, text: text, selection: selection?.text, modelId: modelId) { piece in
                    Task { @MainActor in
                        if self.chatScope == scope { self.streaming = (self.streaming ?? "") + piece }
                    }
                }
                if chatScope == scope { messages.append(msg) }
            } catch {
                if chatScope == scope { chatError = error.localizedDescription }
            }
            if chatScope == scope { streaming = nil }
            engineState = loadedModelId == nil ? .idle : .ready
        }
    }

    func stopGeneration() { Task { await engine.cancel() } }

    func clearChat() {
        chat.clear(chatScope)
        messages = []
    }

    // MARK: stats

    func refreshStats() {
        statsSummary = stats.summary()
        vocabulary = vocab.list()
        recentQuestions = chat.recentQuestions()
    }

    private func startHeartbeat() {
        heartbeat = Timer.scheduledTimer(withTimeInterval: TimeInterval(StatsService.heartbeatSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, NSApp.isActive, NSApp.keyWindow != nil else { return }
                let book = self.activeBook
                self.stats.heartbeat(bookId: book?.id, page: book?.lastPage)
            }
        }
    }
}
