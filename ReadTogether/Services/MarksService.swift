import Foundation

/// Highlights the user made, persisted so they survive reopening the PDF.
final class MarksService {
    private let store = JSONStore<[Mark]>(Paths.marks) { [] }
    func all() -> [Mark] { store.read() }
    func marks(for bookId: String) -> [Mark] { all().filter { $0.bookId == bookId }.sorted { ($0.pageIndex, $0.createdAt) < ($1.pageIndex, $1.createdAt) } }
    func add(_ m: Mark) { store.update { $0.append(m) } }
    func update(_ id: String, _ fn: (inout Mark) -> Void) { store.update { if let i = $0.firstIndex(where: { $0.id == id }) { fn(&$0[i]) } } }
    func remove(_ id: String) { store.update { $0.removeAll { $0.id == id } } }
    func removeAll(bookId: String) { store.update { $0.removeAll { $0.bookId == bookId } } }
}
