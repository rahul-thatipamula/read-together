import Foundation

struct DownloadProgress: Equatable {
    var downloaded: Int64
    var total: Int64
    var bytesPerSecond: Double
    var fraction: Double { total > 0 ? Double(downloaded) / Double(total) : 0 }
}

/// Downloads GGUF files into Application Support/models/<id>/ with progress and cancel.
@MainActor
final class ModelService: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published private(set) var progress: [String: DownloadProgress] = [:]
    @Published private(set) var installed: Set<String> = []

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var taskIds: [Int: String] = [:]
    private var speedSamples: [String: (Date, Int64)] = [:]
    private var continuations: [String: CheckedContinuation<URL, Error>] = [:]
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)

    override init() {
        super.init()
        refresh()
    }

    func path(for id: String) -> URL? {
        guard let m = ModelCatalog.find(id) else { return nil }
        let url = Paths.models.appendingPathComponent(id).appendingPathComponent(m.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func refresh() {
        installed = Set(ModelCatalog.all.compactMap { path(for: $0.id) != nil ? $0.id : nil })
    }

    func download(_ id: String) async throws {
        guard let m = ModelCatalog.find(id), tasks[id] == nil else { return }
        progress[id] = DownloadProgress(downloaded: 0, total: m.sizeBytes, bytesPerSecond: 0)
        let task = session.downloadTask(with: m.url)
        tasks[id] = task
        taskIds[task.taskIdentifier] = id
        defer { tasks[id] = nil; taskIds[task.taskIdentifier] = nil; progress[id] = nil; speedSamples[id] = nil }
        let tmp: URL = try await withCheckedThrowingContinuation { cont in
            continuations[id] = cont
            task.resume()
        }
        let dir = Paths.models.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(m.fileName)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        refresh()
    }

    func cancel(_ id: String) { tasks[id]?.cancel() }

    func delete(_ id: String) {
        cancel(id)
        try? FileManager.default.removeItem(at: Paths.models.appendingPathComponent(id))
        refresh()
    }

    func cancelAll() { tasks.values.forEach { $0.cancel() } }

    // MARK: URLSessionDownloadDelegate

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Move out of the temp location synchronously — it is deleted when this method returns.
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.moveItem(at: location, to: keep)
        let taskId = downloadTask.taskIdentifier
        Task { @MainActor in
            guard let id = self.taskIds[taskId] else { return }
            self.continuations.removeValue(forKey: id)?.resume(returning: keep)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let taskId = downloadTask.taskIdentifier
        Task { @MainActor in
            guard let id = self.taskIds[taskId] else { return }
            let now = Date()
            var speed = self.progress[id]?.bytesPerSecond ?? 0
            if let (t, b) = self.speedSamples[id], now.timeIntervalSince(t) >= 1 {
                speed = Double(totalBytesWritten - b) / now.timeIntervalSince(t)
                self.speedSamples[id] = (now, totalBytesWritten)
            } else if self.speedSamples[id] == nil {
                self.speedSamples[id] = (now, totalBytesWritten)
            }
            let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : (self.progress[id]?.total ?? 0)
            self.progress[id] = DownloadProgress(downloaded: totalBytesWritten, total: total, bytesPerSecond: speed)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let taskId = task.taskIdentifier
        Task { @MainActor in
            guard let id = self.taskIds[taskId] else { return }
            self.continuations.removeValue(forKey: id)?.resume(throwing: error)
        }
    }
}
