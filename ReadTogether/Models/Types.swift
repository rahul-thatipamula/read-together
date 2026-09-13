import Foundation

/// A book in the library. The PDF is copied into Application Support.
struct Book: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var fileName: String
    var pageCount: Int
    var addedAt: Date
    var indexed: Bool
    var lastPage: Int
}

struct Citation: Codable, Hashable {
    var page: Int
    var snippet: String
    var bookId: String?
    var bookTitle: String?
}

enum Role: String, Codable { case user, assistant }

struct ChatMessage: Identifiable, Codable, Hashable {
    var id: String
    var role: Role
    var content: String
    var citations: [Citation]?
    var createdAt: Date
}

/// A chunk of a book's text with its embedding.
struct Chunk: Codable {
    var id: String
    var page: Int
    var text: String
    var embedding: [Float]
}

struct ScoredChunk {
    var chunk: Chunk
    var bookId: String
    var score: Float
}

struct MemoryItem: Codable {
    var id: String
    var scope: String
    var bookTitle: String?
    var question: String
    var answer: String
    var createdAt: Date
    var embedding: [Float]
}

struct VocabEntry: Identifiable, Codable, Hashable {
    var id: String
    var word: String
    var definition: String
    var bookId: String?
    var bookTitle: String?
    var page: Int?
    var createdAt: Date
}

/// A highlight the user made in a PDF. Bounds are in PDF page space.
struct Mark: Identifiable, Codable, Hashable {
    var id: String
    var bookId: String
    var pageIndex: Int
    var text: String
    var rects: [CGRect]
    var color: MarkColor
    var note: String?
    var createdAt: Date
}

enum MarkColor: String, Codable, CaseIterable {
    case yellow, green, blue, pink, orange
}

struct BookDayStats: Codable {
    var readingSeconds: Int = 0
    var pages: [Int] = []
    var questions: Int = 0
}

struct DayStats: Codable {
    var appSeconds: Int = 0
    var readingSeconds: Int = 0
    var questions: Int = 0
    var wordsLookedUp: Int = 0
    var byBook: [String: BookDayStats] = [:]
}

struct BookTotals {
    var readingSeconds = 0
    var pagesRead = 0
    var questions = 0
    var lastReadAt = Date.distantPast
}

struct StatsSummary {
    var today: DayStats
    var days: [(date: String, stats: DayStats)]
    var totalAppSeconds: Int
    var totalReadingSeconds: Int
    var totalQuestions: Int
    var totalWords: Int
    var totalPages: Int
    var streakDays: Int
    var perBook: [String: BookTotals]
}

enum EngineState: Equatable { case idle, loading, ready, generating, error(String) }

/// Chat scope: a book id, or `library` for all books.
enum Scope: Hashable {
    case library
    case book(String)

    var key: String {
        switch self {
        case .library: return "library"
        case .book(let id): return id
        }
    }
    var bookId: String? {
        if case .book(let id) = self { return id }
        return nil
    }
}
