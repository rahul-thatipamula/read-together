import SwiftUI
import PDFKit

/// PDFKit wrapper: continuous scrolling, pinch/⌘± zoom, text selection, persisted highlights.
struct PDFKitView: NSViewRepresentable {
    let url: URL
    let book: Book
    let state: AppState
    let marks: [Mark]
    @Binding var currentPage: Int
    @Binding var jumpToPage: Int?
    /// Called when the user picks "Ask…" from the selection popover.
    let onAsk: (PDFSelectionInfo) -> Void

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.pageShadowsEnabled = true
        view.backgroundColor = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua]) == .darkAqua ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.91, alpha: 1) }
        view.document = PDFDocument(url: url)
        view.delegate = context.coordinator
        context.coordinator.view = view

        let nc = NotificationCenter.default
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged), name: .PDFViewPageChanged, object: view)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.selectionChanged), name: .PDFViewSelectionChanged, object: view)

        if let page = view.document?.page(at: max(0, currentPage - 1)) {
            DispatchQueue.main.async { view.go(to: page) }
        }
        context.coordinator.apply(marks: marks)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if let p = jumpToPage, let page = view.document?.page(at: p - 1) {
            view.go(to: page)
            DispatchQueue.main.async { jumpToPage = nil }
        }
        if context.coordinator.appliedMarkIds != Set(marks.map(\.id)) {
            context.coordinator.apply(marks: marks)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PDFViewDelegate {
        var parent: PDFKitView
        weak var view: PDFView?
        var appliedMarkIds = Set<String>()
        private var annotations: [PDFAnnotation] = []
        private var selectionDebounce: DispatchWorkItem?
        private var popover: NSPopover?
        private var lastShownText = ""

        init(_ parent: PDFKitView) { self.parent = parent }

        @objc func pageChanged() {
            guard let view, let page = view.currentPage, let doc = view.document else { return }
            let n = doc.index(for: page) + 1
            if n != parent.currentPage { DispatchQueue.main.async { self.parent.currentPage = n } }
        }

        @objc func selectionChanged() {
            selectionDebounce?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.publishSelection() }
            selectionDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }

        private func publishSelection() {
            // Wait until the mouse is released so the bar doesn't flicker mid-drag.
            if NSEvent.pressedMouseButtons != 0 { selectionChanged(); return }
            guard let view, let sel = view.currentSelection, let text = sel.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty, let page = sel.pages.first, let doc = view.document else {
                hidePopover()
                return
            }
            if text == lastShownText, popover?.isShown == true { return }
            let rects = sel.selectionsByLine().compactMap { line -> CGRect? in
                guard line.pages.first == page else { return nil }
                return line.bounds(for: page)
            }
            let viewRect = view.convert(sel.bounds(for: page), from: page)
            let info = PDFSelectionInfo(text: text, pageIndex: doc.index(for: page), rects: rects, anchor: CGPoint(x: viewRect.midX, y: viewRect.minY))
            showPopover(for: info, at: viewRect, in: view)
        }

        private func showPopover(for info: PDFSelectionInfo, at rect: CGRect, in view: PDFView) {
            hidePopover()
            let bar = SelectionBar(book: parent.book, selection: info,
                                   ask: { [weak self] in self?.hidePopover(); self?.parent.onAsk(info) },
                                   done: { [weak self] in self?.hidePopover(); self?.view?.clearSelection() })
                .environmentObject(parent.state)
            let host = NSHostingController(rootView: bar)
            let pop = NSPopover()
            pop.contentViewController = host
            pop.behavior = .semitransient
            pop.animates = true
            // Anchor to the visible part of the selection so the popover never goes off-screen.
            let anchor = rect.intersection(view.bounds).isNull ? rect : rect.intersection(view.bounds)
            pop.show(relativeTo: anchor, of: view, preferredEdge: .maxY)
            popover = pop
            lastShownText = info.text
        }

        func hidePopover() {
            popover?.performClose(nil)
            popover = nil
            lastShownText = ""
        }

        func apply(marks: [Mark]) {
            guard let view, let doc = view.document else { return }
            for a in annotations { a.page?.removeAnnotation(a) }
            annotations = []
            for m in marks {
                guard let page = doc.page(at: m.pageIndex) else { continue }
                for r in m.rects {
                    let a = PDFAnnotation(bounds: r, forType: .highlight, withProperties: nil)
                    a.color = m.color.nsColor.withAlphaComponent(0.45)
                    a.contents = m.id
                    page.addAnnotation(a)
                    annotations.append(a)
                }
            }
            appliedMarkIds = Set(marks.map(\.id))
        }
    }
}

extension MarkColor {
    var nsColor: NSColor {
        switch self {
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .pink: return .systemPink
        case .orange: return .systemOrange
        }
    }
    var color: Color { Color(nsColor: nsColor) }
}
