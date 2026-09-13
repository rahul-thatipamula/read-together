import SwiftUI

struct ChatPanel: View {
    @EnvironmentObject var state: AppState
    var book: Book?
    var wide = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var ready: Bool { state.engineState == .ready || state.engineState == .generating }
    private var busy: Bool { state.streaming != nil }
    private var allBooks: Bool { state.chatScope == .library }
    private var indexedCount: Int { state.books.filter(\.indexed).count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            notices
            messagesList
            Divider()
            input
        }
        .background(.background)
    }

    private var header: some View {
        HStack {
            if let book {
                Picker("", selection: Binding(get: { allBooks }, set: { state.setScope($0 ? .library : .book(book.id)) })) {
                    Text("This book").tag(false)
                    Text("All books").tag(true)
                }
                .pickerStyle(.segmented).frame(width: 180).labelsHidden()
            } else {
                Text("Ask across all books").font(.headline)
            }
            Spacer()
            Button("Clear") { state.clearChat() }.disabled(state.messages.isEmpty).controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder private var notices: some View {
        if !ready {
            notice(state.engineState == .loading ? "Loading model…" : "No model loaded.", action: state.engineState == .loading ? nil : ("Set one up", { state.selection = .models }))
        } else if let book, !allBooks, !book.indexed {
            notice("This book isn't indexed yet — answers will be guesses.", action: ("Index now", { state.indexBook(book) }))
        } else if allBooks, indexedCount == 0 {
            notice("No indexed books yet. Open a book and click “Index for chat”.", action: nil)
        }
    }

    private func notice(_ text: String, action: (String, () -> Void)?) -> some View {
        HStack(spacing: 6) {
            Text(text)
            if let (title, fn) = action { Button(title, action: fn).buttonStyle(.link) }
            Spacer()
        }
        .font(.callout).foregroundStyle(.secondary)
        .padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12).padding(.top, 8)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if state.messages.isEmpty && state.streaming == nil { hint }
                    ForEach(state.messages) { m in MessageBubble(message: m, book: book) }
                    if let s = state.streaming {
                        MessageBubble(message: ChatMessage(id: "streaming", role: .assistant, content: s.isEmpty ? "…" : ChatService.stripThinking(s) + (s.contains("<think>") && !s.contains("</think>") ? "Thinking…" : ""), createdAt: Date()), book: book)
                    }
                    if let e = state.chatError {
                        Text(e).font(.callout).foregroundStyle(.red)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(12)
                .frame(maxWidth: wide ? 760 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: state.messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom") } }
            .onChange(of: state.streaming) { _, _ in proxy.scrollTo("bottom") }
        }
    }

    private var hint: some View {
        Group {
            if allBooks {
                Text("Searches every indexed book (\(indexedCount)) and everything you asked before. Try *“Which book talked about stoicism?”* or *“What did I ask last week?”*")
            } else {
                Text("Try *“Who is the narrator?”*, *“What happened in the last chapter I read?”*, or *“define ephemeral”*. Select text in the book for more actions.")
            }
        }
        .font(.callout).foregroundStyle(.secondary)
    }

    private var input: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button { draft = "define "; focused = true } label: { Image(systemName: "character.book.closed") }
                .buttonStyle(.borderless).help("Look up a word").disabled(!ready)
            TextField(placeholder, text: $draft, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(1...5).focused($focused).disabled(!ready)
                .padding(8).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                .onSubmit(submit)
            if busy {
                Button { state.stopGeneration() } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(.borderedProminent).tint(.red)
            } else {
                Button(action: submit) { Image(systemName: "arrow.up") }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: [])
                    .disabled(!ready || draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
    }

    private var placeholder: String {
        if !ready { return "Load a model to start chatting" }
        return allBooks ? "Ask about any book, or what you asked before…" : "Ask about what you're reading, or “define <word>”…"
    }

    private func submit() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, ready, !busy else { return }
        draft = ""
        state.send(t)
    }
}

struct MessageBubble: View {
    @EnvironmentObject var state: AppState
    let message: ChatMessage
    var book: Book?

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            Group {
                if message.role == .user {
                    Text(message.content)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                } else {
                    Text(markdown(message.content))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .textSelection(.enabled)
            if let cites = message.citations, !cites.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(unique(cites), id: \.self) { c in
                        Button {
                            if let id = c.bookId, id != book?.id, let b = state.books.first(where: { $0.id == id }) {
                                state.library.update(id) { $0.lastPage = c.page }
                                state.open(b)
                            } else {
                                state.jumpToPage = c.page
                            }
                        } label: {
                            Text((c.bookTitle.map { "\($0.prefix(18))… · " } ?? "") + "p. \(c.page)")
                                .font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                        .buttonStyle(.plain).help(c.snippet)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private func unique(_ cs: [Citation]) -> [Citation] {
        var seen = Set<String>()
        return cs.filter { seen.insert("\($0.bookId ?? "")-\($0.page)").inserted }
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
