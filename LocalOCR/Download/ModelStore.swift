import Foundation

/// Downloads, checks and deletes the model files of each engine.
/// Files go to Application Support/Models, excluded from iCloud backup (they can be fetched again).
@MainActor
final class ModelStore: NSObject, ObservableObject {
    enum Status: Equatable {
        case notInstalled
        case downloading(Double)   // 0...1
        case installed
        case failed(String)
    }

    @Published private(set) var status: [EngineKind: Status] = [:]

    private var tasks: [EngineKind: Task<Void, Never>] = [:]

    override init() {
        super.init()
        refresh()
    }

    func refresh() {
        for kind in EngineKind.allCases {
            if case .downloading = status[kind] { continue }
            status[kind] = isInstalled(kind) ? .installed : .notInstalled
        }
    }

    func isInstalled(_ kind: EngineKind) -> Bool {
        kind.files.allSatisfy { file in
            let url = ModelFiles.directory.appendingPathComponent(file.localName)
            return Self.size(of: url) == file.size
        }
    }

    var installedEngines: [EngineKind] {
        EngineKind.allCases.filter { status[$0] == .installed }
    }

    /// Bytes the downloaded models take on this device.
    var usedBytes: Int64 {
        EngineKind.allCases.filter { isInstalled($0) && $0.needsDownload }.reduce(0) { $0 + $1.downloadSize }
    }

    func download(_ kind: EngineKind) {
        guard tasks[kind] == nil else { return }
        status[kind] = .downloading(0)
        tasks[kind] = Task { [weak self] in
            await self?.run(kind)
        }
    }

    func cancel(_ kind: EngineKind) {
        tasks[kind]?.cancel()
        tasks[kind] = nil
        status[kind] = isInstalled(kind) ? .installed : .notInstalled
    }

    func delete(_ kind: EngineKind) {
        cancel(kind)
        for file in kind.files {
            try? FileManager.default.removeItem(at: ModelFiles.directory.appendingPathComponent(file.localName))
        }
        status[kind] = .notInstalled
    }

    private func run(_ kind: EngineKind) async {
        defer { tasks[kind] = nil }
        do {
            try FileManager.default.createDirectory(at: ModelFiles.directory, withIntermediateDirectories: true)
            var dir = ModelFiles.directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)

            let total = Double(kind.downloadSize)
            var done: Int64 = 0
            for file in kind.files {
                let dest = ModelFiles.directory.appendingPathComponent(file.localName)
                if Self.size(of: dest) == file.size {
                    done += file.size
                    continue
                }
                let base = done
                let tmp = try await Self.fetch(file.url) { written in
                    Task { @MainActor [weak self] in
                        guard case .downloading = self?.status[kind] else { return }
                        self?.status[kind] = .downloading(Double(base + written) / total)
                    }
                }
                try Task.checkCancellation()
                let got = Self.size(of: tmp)
                guard got == file.size else {
                    try? FileManager.default.removeItem(at: tmp)
                    throw DownloadError.sizeMismatch(file.localName, expected: file.size, got: got ?? 0)
                }
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
                done += file.size
                status[kind] = .downloading(Double(done) / total)
            }
            status[kind] = .installed
        } catch is CancellationError {
            status[kind] = isInstalled(kind) ? .installed : .notInstalled
        } catch let error as URLError where error.code == .cancelled {
            status[kind] = isInstalled(kind) ? .installed : .notInstalled
        } catch {
            status[kind] = .failed(error.localizedDescription)
        }
    }

    enum DownloadError: LocalizedError {
        case sizeMismatch(String, expected: Int64, got: Int64)
        case http(Int)

        var errorDescription: String? {
            switch self {
            case let .sizeMismatch(name, expected, got):
                return String(localized: "download_size_mismatch",
                              defaultValue: "\(name) の大きさが合いません（\(got) / \(expected) バイト）。もう一度お試しください。")
            case let .http(code):
                return String(localized: "download_http_error", defaultValue: "サーバーから取得できませんでした（\(code)）。")
            }
        }
    }

    /// Downloads to a temporary file in the model folder (same volume, so the move is cheap).
    private static func fetch(_ url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        let delegate = ProgressDelegate(progress: progress)
        let (tmp, response) = try await URLSession.shared.download(from: url, delegate: delegate)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: tmp)
            throw DownloadError.http(http.statusCode)
        }
        let staged = ModelFiles.directory.appendingPathComponent(UUID().uuidString + ".part")
        try FileManager.default.moveItem(at: tmp, to: staged)
        return staged
    }

    nonisolated static func size(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }
}

private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Int64) -> Void
    private var last = Date.distantPast

    init(progress: @escaping @Sendable (Int64) -> Void) { self.progress = progress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = Date()
        guard now.timeIntervalSince(last) > 0.2 else { return }
        last = now
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
