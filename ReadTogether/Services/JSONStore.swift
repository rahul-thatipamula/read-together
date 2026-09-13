import Foundation

/// Tiny persistent JSON file with an in-memory cache. Atomic writes.
final class JSONStore<T: Codable> {
    private let url: URL
    private let initial: () -> T
    private var cache: T?
    private let queue = DispatchQueue(label: "jsonstore." + UUID().uuidString)

    init(_ url: URL, initial: @escaping () -> T) {
        self.url = url
        self.initial = initial
    }

    func read() -> T {
        queue.sync {
            if let c = cache { return c }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let data = try? Data(contentsOf: url), let v = try? decoder.decode(T.self, from: data) {
                cache = v
            } else {
                cache = initial()
            }
            return cache!
        }
    }

    func write(_ value: T) {
        queue.sync {
            cache = value
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(value) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    @discardableResult
    func update(_ fn: (inout T) -> Void) -> T {
        var v = read()
        fn(&v)
        write(v)
        return v
    }
}
