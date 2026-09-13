import SwiftUI

struct AskView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        ChatPanel(book: nil, wide: true)
            .navigationTitle("Ask")
            .onAppear { state.setScope(.library) }
    }
}
