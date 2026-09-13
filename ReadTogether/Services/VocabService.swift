import Foundation

final class VocabService {
    private let store = JSONStore<[VocabEntry]>(Paths.vocabulary) { [] }
    func list() -> [VocabEntry] { store.read() }

    func add(word: String, definition: String, bookId: String?, bookTitle: String?, page: Int?) {
        store.update { list in
            list.removeAll { $0.word.lowercased() == word.lowercased() && $0.bookId == bookId }
            list.insert(VocabEntry(id: UUID().uuidString, word: word, definition: definition, bookId: bookId, bookTitle: bookTitle, page: page, createdAt: Date()), at: 0)
        }
    }
    func remove(_ id: String) { store.update { $0.removeAll { $0.id == id } } }
}
