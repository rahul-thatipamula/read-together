import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject var state: AppState
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            if let s = state.statsSummary {
                VStack(alignment: .leading, spacing: 22) {
                    tiles(s)
                    section("Last 14 days") { chart(s) }
                    section("By book") { byBook(s) }
                    section("Words you looked up") { vocab }
                    section("Recent questions") { recent }
                }
                .padding(28)
            } else {
                ProgressView().padding()
            }
        }
        .navigationTitle("Reading")
        .navigationSubtitle(state.statsSummary.map { $0.streakDays > 0 ? "\($0.streakDays)-day streak" : "No streak yet" } ?? "")
        .onAppear(perform: state.refreshStats)
        .onReceive(timer) { _ in state.refreshStats() }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func tiles(_ s: StatsSummary) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            Tile(label: "Read today", value: fmt(s.today.readingSeconds), sub: "\(fmt(s.today.appSeconds)) in app")
            Tile(label: "Questions today", value: "\(s.today.questions)", sub: "\(s.today.wordsLookedUp) words looked up")
            Tile(label: "Total reading", value: fmt(s.totalReadingSeconds), sub: "\(s.totalPages) pages")
            Tile(label: "Total questions", value: "\(s.totalQuestions)", sub: "\(s.totalWords) words")
        }
    }

    private func chart(_ s: StatsSummary) -> some View {
        Chart(s.days, id: \.date) { d in
            BarMark(x: .value("Day", String(d.date.suffix(5))), y: .value("Minutes", d.stats.readingSeconds / 60))
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(3)
        }
        .chartYAxisLabel("min")
        .frame(height: 140)
        .padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    private func byBook(_ s: StatsSummary) -> some View {
        let rows = s.perBook.sorted { $0.value.lastReadAt > $1.value.lastReadAt }
        return Group {
            if rows.isEmpty {
                Text("Open a book to start tracking.").foregroundStyle(.secondary)
            } else {
                Table(rows.map { r in BookRow(id: r.key, title: state.books.first { b in b.id == r.key }?.title ?? "Removed book", t: r.value) }) {
                    TableColumn("Book", value: \.title)
                    TableColumn("Time") { Text(fmt($0.t.readingSeconds)) }.width(80)
                    TableColumn("Pages") { Text("\($0.t.pagesRead)") }.width(60)
                    TableColumn("Questions") { Text("\($0.t.questions)") }.width(80)
                    TableColumn("Last read") { Text($0.t.lastReadAt.formatted(date: .abbreviated, time: .omitted)) }.width(110)
                }
                .frame(height: CGFloat(rows.count) * 28 + 40)
            }
        }
    }

    private var vocab: some View {
        Group {
            if state.vocabulary.isEmpty {
                Text("Ask “define <word>” or select a word in a book and it lands here.").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(state.vocabulary) { v in
                        DisclosureGroup {
                            Text((try? AttributedString(markdown: v.definition, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(v.definition))
                                .font(.callout).textSelection(.enabled).padding(.vertical, 4)
                        } label: {
                            HStack {
                                Text(v.word).bold()
                                Text([v.bookTitle, v.page.map { "p. \($0)" }].compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary)
                                Spacer()
                                Button { state.vocab.remove(v.id); state.refreshStats() } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                            }
                        }
                        .padding(10).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var recent: some View {
        Group {
            if state.recentQuestions.isEmpty {
                Text("Nothing asked yet.").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 2) {
                    ForEach(state.recentQuestions, id: \.message.id) { q in
                        Button {
                            switch q.scope {
                            case .library: state.selection = .ask
                            case .book(let id): if let b = state.books.first(where: { $0.id == id }) { state.open(b) }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Text(q.message.createdAt.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                                Text(scopeName(q.scope)).foregroundStyle(Color.accentColor).lineLimit(1).frame(width: 150, alignment: .leading)
                                Text(q.message.content).lineLimit(1)
                                Spacer()
                            }
                            .font(.callout).padding(.horizontal, 8).padding(.vertical, 5).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func scopeName(_ s: Scope) -> String {
        switch s {
        case .library: return "All books"
        case .book(let id): return state.books.first { $0.id == id }?.title ?? "Removed book"
        }
    }

    private func fmt(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    private struct BookRow: Identifiable { let id: String; let title: String; let t: BookTotals }
}

struct Tile: View {
    let label: String, value: String, sub: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title, design: .rounded).weight(.semibold))
            Text(sub).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }
}
