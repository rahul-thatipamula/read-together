import SwiftUI
import PDFKit

struct ReaderView: View {
    @EnvironmentObject var state: AppState
    let book: Book

    @State private var page: Int
    @State private var pageField = ""
    @State private var selection: PDFSelectionInfo?
    @State private var showAskSheet = false

    init(book: Book) {
        self.book = book
        _page = State(initialValue: max(1, book.lastPage))
    }

    var body: some View {
        HSplitView {
            pdfArea
                .frame(minWidth: 420)
            if state.chatOpen && !state.focusMode {
                ChatPanel(book: book)
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 520)
            }
        }
        .navigationTitle(book.title)
        .navigationSubtitle(state.focusMode ? "" : "Page \(page) of \(book.pageCount)")
        .toolbar { if !state.focusMode { toolbarContent } }
        .toolbar(state.focusMode ? .hidden : .automatic)
        .onChange(of: page) { _, p in state.setLastPage(book, p); pageField = String(p) }
        .onAppear { pageField = String(page) }
        .sheet(isPresented: $showAskSheet) {
            if let sel = selection { AskAboutSelectionSheet(book: book, selection: sel) }
        }
        .sheet(isPresented: $state.showMarks) { MarksSheet(book: book) }
        .onKeyPress(.escape) {
            if state.focusMode { state.focusMode = false; return .handled }
            return .ignored
        }
    }

    private var pdfArea: some View {
        ZStack(alignment: .bottomTrailing) {
            PDFKitView(url: state.library.fileURL(book), book: book, state: state, marks: state.bookMarks,
                       currentPage: $page, jumpToPage: $state.jumpToPage) { sel in
                selection = sel
                showAskSheet = true
            }
            if state.focusMode {
                focusHint
            }
        }
    }

    private var focusHint: some View {
        HStack(spacing: 8) {
            Text("Page \(page) of \(book.pageCount)")
            Text("·").foregroundStyle(.tertiary)
            Text("Esc to exit focus")
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(false)
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { state.selection = .library } label: { Label("Library", systemImage: "chevron.left") }
        }
        ToolbarItemGroup(placement: .principal) {
            HStack(spacing: 6) {
                Button { go(-1) } label: { Image(systemName: "chevron.up") }.disabled(page <= 1)
                TextField("", text: $pageField)
                    .textFieldStyle(.roundedBorder).frame(width: 52).multilineTextAlignment(.center)
                    .onSubmit { if let n = Int(pageField) { state.jumpToPage = min(max(1, n), book.pageCount) } }
                Text("/ \(book.pageCount)").foregroundStyle(.secondary).monospacedDigit()
                Button { go(1) } label: { Image(systemName: "chevron.down") }.disabled(page >= book.pageCount)
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if let p = state.indexing[book.id] {
                ProgressView(value: p).frame(width: 80)
            } else if !book.indexed {
                Button { state.indexBook(book) } label: { Label("Index for chat", systemImage: "sparkles") }
                    .help("Extract text and build the search index so you can ask questions")
            }
            Button { state.showMarks.toggle() } label: { Label("Marks", systemImage: "highlighter") }
                .help("Your highlights (⇧⌘M)")
            Button { state.chatOpen.toggle() } label: { Label("Chat", systemImage: state.chatOpen ? "sidebar.trailing" : "bubble.left") }
                .help("Show or hide chat (⇧⌘J)")
            Button { state.focusMode = true } label: { Label("Focus", systemImage: "arrow.up.left.and.arrow.down.right") }
                .help("Only the book, full screen (⇧⌘F)")
        }
    }

    private func go(_ delta: Int) { state.jumpToPage = min(max(1, page + delta), book.pageCount) }
}

/// Floating actions that appear above a text selection.
struct SelectionBar: View {
    @EnvironmentObject var state: AppState
    let book: Book
    let selection: PDFSelectionInfo
    let ask: () -> Void
    let done: () -> Void

    private var isSingleWord: Bool { !selection.text.contains(where: { $0.isWhitespace }) && selection.text.count < 40 }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MarkColor.allCases, id: \.self) { c in
                Button { state.addMark(from: selection, book: book, color: c); done() } label: {
                    Circle().fill(c.color).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.primary.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain).padding(4).help("Highlight")
            }
            Divider().frame(height: 18).padding(.horizontal, 4)
            bar("doc.on.doc", "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(selection.text, forType: .string)
                done()
            }
            if isSingleWord {
                bar("character.book.closed", "Define") {
                    state.setScope(.book(book.id)); state.chatOpen = true; state.focusMode = false
                    state.send("define \(selection.text)")
                    done()
                }
            }
            bar("text.magnifyingglass", "Explain") {
                state.setScope(.book(book.id)); state.chatOpen = true; state.focusMode = false
                state.send("Explain this in simple terms.", selection: selection)
                done()
            }
            bar("bubble.left.and.text.bubble.right", "Ask…") { ask() }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    private func bar(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).labelStyle(.titleAndIcon).font(.callout)
        }
        .buttonStyle(.borderless).padding(.horizontal, 4).padding(.vertical, 3)
    }
}

/// "Ask about this selection" with a free prompt and quick intents.
struct AskAboutSelectionSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let book: Book
    let selection: PDFSelectionInfo
    @State private var prompt = ""

    private let quick = ["Explain this simply", "Summarize this", "Why does this matter?", "Give an example", "How does this connect to earlier chapters?"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask about the selection").font(.title2.weight(.semibold))
            ScrollView {
                Text(selection.text).font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .frame(maxHeight: 140)
            .padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            FlowLayout(spacing: 6) {
                ForEach(quick, id: \.self) { q in
                    Button(q) { prompt = q }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            TextField("What do you want to know about this?", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...4)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Ask", action: submit).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20).frame(width: 480)
    }

    private func submit() {
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        state.setScope(.book(book.id)); state.chatOpen = true; state.focusMode = false
        state.send(prompt, selection: selection)
        dismiss()
    }
}

/// List of highlights for the book; click to jump, ask about them, or delete.
struct MarksSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Marks in \(book.title)").font(.title2.weight(.semibold)).lineLimit(1)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if state.bookMarks.isEmpty {
                ContentUnavailableView("No highlights yet", systemImage: "highlighter", description: Text("Select text in the book and pick a color."))
            } else {
                List {
                    ForEach(state.bookMarks) { m in
                        HStack(alignment: .top, spacing: 10) {
                            RoundedRectangle(cornerRadius: 2).fill(m.color.color).frame(width: 4)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(m.text).lineLimit(3).font(.callout)
                                Text("p. \(m.pageIndex + 1) · \(m.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { state.setScope(.book(book.id)); state.chatOpen = true; dismiss()
                                state.send("Explain this in simple terms.", selection: PDFSelectionInfo(text: m.text, pageIndex: m.pageIndex, rects: m.rects, anchor: .zero))
                            } label: { Image(systemName: "bubble.left") }.buttonStyle(.borderless).help("Ask about this")
                            Button(role: .destructive) { state.removeMark(m.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { state.jumpToPage = m.pageIndex + 1; dismiss() }
                    }
                }
                Button("Ask about all marks") {
                    let all = state.bookMarks.map { "(p. \($0.pageIndex + 1)) \($0.text)" }.joined(separator: "\n")
                    state.setScope(.book(book.id)); state.chatOpen = true; dismiss()
                    state.send("Summarize what these highlights have in common and what I should remember.", selection: PDFSelectionInfo(text: all, pageIndex: 0, rects: [], anchor: .zero))
                }
            }
        }
        .padding(20).frame(width: 520, height: 480)
    }
}

/// Minimal wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > w { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}
