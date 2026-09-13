import Foundation

/// All app data lives under ~/Library/Containers/<bundle>/Data/Library/Application Support/Read Together
enum Paths {
    static var data: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Read Together", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var models: URL { sub("models") }
    static var books: URL { sub("books") }
    static var indexes: URL { sub("indexes") }
    static var chats: URL { sub("chats") }
    static var library: URL { data.appendingPathComponent("library.json") }
    static var memory: URL { data.appendingPathComponent("memory.json") }
    static var vocabulary: URL { data.appendingPathComponent("vocabulary.json") }
    static var marks: URL { data.appendingPathComponent("marks.json") }
    static var stats: URL { data.appendingPathComponent("stats.json") }

    private static func sub(_ name: String) -> URL {
        let dir = data.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
