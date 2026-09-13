import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        List(selection: $state.selection) {
            Section {
                Label("Library", systemImage: "books.vertical").tag(SidebarItem.library)
                Label("Ask", systemImage: "bubble.left.and.text.bubble.right").tag(SidebarItem.ask)
                Label("Reading", systemImage: "chart.bar.xaxis").tag(SidebarItem.reading)
                Label("Models", systemImage: "cpu").tag(SidebarItem.models)
            }
            if !state.books.isEmpty {
                Section("Books") {
                    ForEach(state.books) { b in
                        Label(b.title, systemImage: "book.closed")
                            .lineLimit(1)
                            .tag(SidebarItem.book(b.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: state.selection) { _, sel in
            if case .book(let id) = sel, let b = state.books.first(where: { $0.id == id }) { state.open(b) }
            if case .ask = sel { state.setScope(.library) }
        }
        .safeAreaInset(edge: .bottom) { EngineBadge() }
    }
}

/// Small status pill at the bottom of the sidebar.
struct EngineBadge: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Button { state.selection = .models } label: {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).lineLimit(1).font(.callout)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(10)
    }

    private var color: Color {
        switch state.engineState {
        case .ready, .generating: return .green
        case .loading: return .orange
        case .error: return .red
        case .idle: return .secondary
        }
    }
    private var label: String {
        switch state.engineState {
        case .ready: return ModelCatalog.find(state.loadedModelId ?? "")?.name ?? "Ready"
        case .generating: return "Thinking…"
        case .loading: return "Loading model…"
        case .error: return "Engine error"
        case .idle: return "No model loaded"
        }
    }
}
