import Foundation
import CoreGraphics

/// Daily reading/usage stats. Heartbeat every 30 s while the app is active and the user isn't idle.
final class StatsService {
    static let heartbeatSeconds = 30
    private static let idleLimit: Double = 120
    private let store = JSONStore<[String: DayStats]>(Paths.stats) { [:] }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    private static func key(_ d: Date) -> String { dayFormatter.string(from: d) }

    private func bump(_ fn: (inout DayStats) -> Void) {
        store.update { days in
            var day = days[Self.key(Date())] ?? DayStats()
            fn(&day)
            days[Self.key(Date())] = day
        }
    }

    static var secondsIdle: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    func heartbeat(bookId: String?, page: Int?) {
        guard Self.secondsIdle < Self.idleLimit else { return }
        bump { day in
            day.appSeconds += Self.heartbeatSeconds
            guard let bookId else { return }
            day.readingSeconds += Self.heartbeatSeconds
            var b = day.byBook[bookId] ?? BookDayStats()
            b.readingSeconds += Self.heartbeatSeconds
            if let page, !b.pages.contains(page) { b.pages.append(page) }
            day.byBook[bookId] = b
        }
    }

    func countQuestion(bookId: String?) {
        bump { day in
            day.questions += 1
            if let bookId { var b = day.byBook[bookId] ?? BookDayStats(); b.questions += 1; day.byBook[bookId] = b }
        }
    }

    func countWordLookup() { bump { $0.wordsLookedUp += 1 } }

    func summary() -> StatsSummary {
        let days = store.read()
        let cal = Calendar.current
        var last14: [(String, DayStats)] = []
        for i in (0..<14).reversed() {
            let d = cal.date(byAdding: .day, value: -i, to: Date())!
            let k = Self.key(d)
            last14.append((k, days[k] ?? DayStats()))
        }
        var app = 0, reading = 0, questions = 0, words = 0
        var perBook: [String: BookTotals] = [:]
        var pagesPerBook: [String: Set<Int>] = [:]
        for (k, day) in days {
            app += day.appSeconds; reading += day.readingSeconds; questions += day.questions; words += day.wordsLookedUp
            for (bid, b) in day.byBook {
                var t = perBook[bid] ?? BookTotals()
                t.readingSeconds += b.readingSeconds
                t.questions += b.questions
                if let d = Self.dayFormatter.date(from: k), d > t.lastReadAt { t.lastReadAt = d }
                perBook[bid] = t
                pagesPerBook[bid, default: []].formUnion(b.pages)
            }
        }
        var pages = 0
        for (bid, set) in pagesPerBook { perBook[bid]?.pagesRead = set.count; pages += set.count }

        var streak = 0
        var cursor = Date()
        func has(_ d: Date) -> Bool { (days[Self.key(d)]?.readingSeconds ?? 0) > 0 }
        if !has(cursor) { cursor = cal.date(byAdding: .day, value: -1, to: cursor)! }
        while has(cursor) { streak += 1; cursor = cal.date(byAdding: .day, value: -1, to: cursor)! }

        return StatsSummary(today: days[Self.key(Date())] ?? DayStats(), days: last14.map { (date: $0.0, stats: $0.1) },
                            totalAppSeconds: app, totalReadingSeconds: reading, totalQuestions: questions,
                            totalWords: words, totalPages: pages, streakDays: streak, perBook: perBook)
    }
}
