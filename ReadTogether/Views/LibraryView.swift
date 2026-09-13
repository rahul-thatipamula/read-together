import SwiftUI
import PDFKit

struct LibraryView: View {
    @EnvironmentObject var state: AppState
    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 20)]

    var body: some View {
        Group {
            if state.books.isEmpty {
                ContentUnavailableView {
                    Label("No books yet", systemImage: "books.vertical")
                } description: {
                    Text("Add a PDF, then ask anything about it — even the parts you forgot.")
                } actions: {
                    Button("Add Book…") { state.importPDF() }.buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(state.books) { book in
                            BookCard(book: book)
                        }
                    }
                    .padding(28)
                }
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { state.importPDF() } label: { Label("Add Book", systemImage: "plus") }
            }
        }
    }
}

struct BookCard: View {
    @EnvironmentObject var state: AppState
    let book: Book
    @State private var thumb: NSImage?
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                if let thumb {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(hover ? 0.25 : 0.12), radius: hover ? 12 : 6, y: 4)
            .scaleEffect(hover ? 1.02 : 1)

            Text(book.title).font(.headline).lineLimit(2)
            HStack(spacing: 4) {
                if let p = state.indexing[book.id] {
                    ProgressView(value: p).frame(width: 60)
                    Text("Indexing").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(book.pageCount > 0 ? "\(book.pageCount) pages" : "PDF")
                    Text("·")
                    Text(book.indexed ? "Indexed" : "Not indexed")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            if book.lastPage > 1 {
                Text("Continue from p. \(book.lastPage)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .onTapGesture { state.open(book) }
        .contextMenu {
            Button("Open") { state.open(book) }
            Button(book.indexed ? "Re-index" : "Index for chat") { state.indexBook(book) }
            Divider()
            Button("Remove", role: .destructive) { state.remove(book) }
        }
        .task { thumb = await Self.thumbnail(for: state.library.fileURL(book)) }
    }

    static func thumbnail(for url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: CGSize(width: 340, height: 460), for: .cropBox)
        }.value
    }
}
