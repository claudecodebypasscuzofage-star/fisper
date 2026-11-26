import Foundation

/// Downloads Whisper models into ~/Library/Application Support/Fisper/models with progress.
@MainActor
final class ModelManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress: [String: Double] = [:]     // modelID -> 0...1 while downloading
    @Published var errors: [String: String] = [:]
    @Published var revision = 0                          // bump to refresh "downloaded" state in views

    private lazy var session: URLSession = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    private var tasks: [Int: String] = [:]
    var onFinished: ((String) -> Void)?

    func isDownloading(_ id: String) -> Bool { progress[id] != nil }

    func download(_ model: WhisperModelInfo) {
        guard progress[model.id] == nil else { return }
        errors[model.id] = nil
        progress[model.id] = 0
        let task = session.downloadTask(with: model.url)
        tasks[task.taskIdentifier] = model.id
        task.resume()
    }

    func cancel(_ id: String) {
        session.getAllTasks { all in
            Task { @MainActor in
                for t in all where self.tasks[t.taskIdentifier] == id { t.cancel() }
                self.progress[id] = nil
            }
        }
    }

    func delete(_ model: WhisperModelInfo) {
        try? FileManager.default.removeItem(at: model.localURL)
        revision += 1
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskIdentifier
        let frac = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        MainActor.assumeIsolated {
            if let m = tasks[id] { progress[m] = frac }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let id = downloadTask.taskIdentifier
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        // the temp file is deleted when this method returns — move it synchronously
        let staging = Paths.models.appendingPathComponent("download-\(id).part")
        try? FileManager.default.removeItem(at: staging)
        let moved = (try? FileManager.default.moveItem(at: location, to: staging)) != nil
        MainActor.assumeIsolated {
            guard let m = tasks[id] else { return }
            let info = WhisperModelInfo.info(for: m)
            if status == 200 && moved {
                try? FileManager.default.removeItem(at: info.localURL)
                do {
                    try FileManager.default.moveItem(at: staging, to: info.localURL)
                    Log.info("model downloaded: \(m)")
                    onFinished?(m)
                } catch { errors[m] = error.localizedDescription }
            } else {
                errors[m] = "Download failed (HTTP \(status))"
                try? FileManager.default.removeItem(at: staging)
            }
            progress[m] = nil
            tasks[id] = nil
            revision += 1
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let id = task.taskIdentifier
        MainActor.assumeIsolated {
            guard let m = tasks[id] else { return }
            if (error as NSError).code != NSURLErrorCancelled { errors[m] = error.localizedDescription }
            progress[m] = nil
            tasks[id] = nil
        }
    }
}
