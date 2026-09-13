import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            detail
        }
        .onChange(of: state.focusMode) { _, focus in
            withAnimation(.easeInOut(duration: 0.25)) { columns = focus ? .detailOnly : .all }
            if let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) != focus {
                window.toggleFullScreen(nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            if state.focusMode { state.focusMode = false }
        }
    }

    @ViewBuilder private var detail: some View {
        switch state.selection {
        case .library, .none: LibraryView()
        case .ask: AskView()
        case .reading: StatsView()
        case .models: ModelsView()
        case .book(let id):
            if let book = state.books.first(where: { $0.id == id }) {
                ReaderView(book: book).id(book.id)
            } else {
                LibraryView()
            }
        }
    }
}
