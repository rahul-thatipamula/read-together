import Foundation

/// `Read Together --selftest` — exercises the engine + RAG pipeline headlessly and exits.
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }

    @MainActor static func run(_ state: AppState) async {
        func log(_ s: String) { FileHandle.standardOutput.write((s + "\n").data(using: .utf8)!) }
        let t0 = Date()
        do {
            log("embeddings available: \(state.embeddings.isAvailable)")
            guard let modelId = ModelCatalog.all.map(\.id).first(where: { state.models.installed.contains($0) }) else {
                log("no model installed"); exit(1)
            }
            try await state.loadModel(modelId)
            log("loaded \(modelId) in \(Int(Date().timeIntervalSince(t0)))s")

            guard let book = state.books.first else { log("no books"); exit(1) }
            let t1 = Date()
            try state.library.index(book) { _ in }
            state.refreshBooks()
            log("indexed \"\(book.title)\" (\(book.pageCount) pages) in \(Int(Date().timeIntervalSince(t1)))s")

            let t2 = Date()
            var streamed = 0
            let a = try await state.chat.send(scope: .book(book.id), text: "What are the main topics covered in this book?", modelId: modelId) { _ in streamed += 1 }
            log("answer (\(streamed) pieces, \(Int(Date().timeIntervalSince(t2)))s):\n\(a.content.prefix(600))\ncitations: \(a.citations?.map(\.page) ?? [])")

            let d = try await state.chat.send(scope: .book(book.id), text: "define requirement", modelId: modelId) { _ in }
            log("define:\n\(d.content.prefix(300))")
            log("vocab count: \(state.vocab.list().count)")

            let r = try await state.chat.send(scope: .library, text: "What did I ask before about this book?", modelId: modelId) { _ in }
            log("recall:\n\(r.content.prefix(400))")

            log("stats: \(state.stats.summary().totalQuestions) questions")
            await state.engine.unload()
            log("unloaded; total \(Int(Date().timeIntervalSince(t0)))s")
            exit(0)
        } catch {
            log("FAILED: \(error)")
            exit(2)
        }
    }
}
