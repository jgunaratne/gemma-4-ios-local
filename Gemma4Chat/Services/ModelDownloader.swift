import Foundation
import OSLog

private let logger = Logger(subsystem: "com.google.Gemma4Chat", category: "ModelDownloader")

/// Download status for a model.
enum DownloadStatus: Equatable {
  case notDownloaded
  case downloading(progress: Double)
  case downloaded
  case failed(message: String)

  static func == (lhs: DownloadStatus, rhs: DownloadStatus) -> Bool {
    switch (lhs, rhs) {
    case (.notDownloaded, .notDownloaded): return true
    case (.downloaded, .downloaded): return true
    case let (.downloading(a), .downloading(b)): return a == b
    case let (.failed(a), .failed(b)): return a == b
    default: return false
    }
  }

  var isDownloaded: Bool {
    if case .downloaded = self { return true }
    return false
  }

  var isDownloading: Bool {
    if case .downloading = self { return true }
    return false
  }
}

/// Manages model file downloads and local storage.
@MainActor
@Observable
class ModelDownloader {
  /// Download status per model ID.
  var downloadStatuses: [String: DownloadStatus] = [:]

  private var activeDownloads: [String: URLSessionDownloadTask] = [:]
  private var downloadDelegates: [String: DownloadDelegate] = [:]
  private var downloadSessions: [String: URLSession] = [:]

  init() {
    // Check which models are already downloaded.
    for model in GemmaModel.allModels {
      let path = Self.modelPath(for: model)
      if FileManager.default.fileExists(atPath: path) {
        downloadStatuses[model.id] = .downloaded
      } else {
        downloadStatuses[model.id] = .notDownloaded
      }
    }
  }

  /// Returns the local file path for a model.
  static func modelPath(for model: GemmaModel) -> String {
    let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let modelDir = documentsDir.appendingPathComponent("models").appendingPathComponent(model.id)
    let fileName =
      model.downloadURL.lastPathComponent.replacingOccurrences(of: "?download=true", with: "")
    return modelDir.appendingPathComponent(fileName).path
  }

  /// Returns the local directory for a model.
  private static func modelDirectory(for model: GemmaModel) -> URL {
    let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return documentsDir.appendingPathComponent("models").appendingPathComponent(model.id)
  }

  /// Starts downloading a model.
  func downloadModel(_ model: GemmaModel) {
    guard downloadStatuses[model.id]?.isDownloading != true else { return }

    print("🌐 [ModelDownloader] Start downloading model: \(model.displayName)")
    print("🌐 [ModelDownloader] Target URL: \(model.downloadURL.absoluteString)")
    print("🌐 [ModelDownloader] Target Path: \(Self.modelPath(for: model))")

    downloadStatuses[model.id] = .downloading(progress: 0)

    let delegate = DownloadDelegate(
      modelId: model.id,
      expectedBytes: model.sizeInBytes
    ) { [weak self] progress in
      print("🌐 [ModelDownloader] Progress update for \(model.displayName): \(Int(progress * 100))%")
      Task { @MainActor in
        self?.downloadStatuses[model.id] = .downloading(progress: progress)
      }
    } onComplete: { [weak self] tempURL, error in
      Task { @MainActor in
        if let error = error {
          print("❌ [ModelDownloader] Download failed for \(model.displayName): \(error.localizedDescription)")
          logger.error("Download failed for \(model.name): \(error.localizedDescription)")
          self?.downloadStatuses[model.id] = .failed(message: error.localizedDescription)
          return
        }

        guard let tempURL = tempURL else {
          print("❌ [ModelDownloader] Download failed for \(model.displayName): No temp file URL received")
          self?.downloadStatuses[model.id] = .failed(message: "No file received")
          return
        }

        do {
          let modelDir = Self.modelDirectory(for: model)
          try FileManager.default.createDirectory(
            at: modelDir, withIntermediateDirectories: true)

          let fileName =
            model.downloadURL.lastPathComponent.replacingOccurrences(
              of: "?download=true", with: "")
          let destURL = modelDir.appendingPathComponent(fileName)

          // Remove existing file if any.
          if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
          }

          print("💾 [ModelDownloader] Saving model file to: \(destURL.path)")
          try FileManager.default.moveItem(at: tempURL, to: destURL)
          print("✅ [ModelDownloader] Model \(model.displayName) saved successfully!")
          self?.downloadStatuses[model.id] = .downloaded
        } catch {
          print("❌ [ModelDownloader] Failed to save \(model.displayName): \(error.localizedDescription)")
          logger.error("Failed to save model: \(error.localizedDescription)")
          self?.downloadStatuses[model.id] = .failed(message: error.localizedDescription)
        }

        self?.activeDownloads[model.id] = nil
        self?.downloadDelegates[model.id] = nil
        self?.downloadSessions[model.id] = nil
      }
    }

    let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    downloadSessions[model.id] = session
    
    // Create request and set Lorry User-Agent (required by dl.google.com CDN).
    var request = URLRequest(url: model.downloadURL)
    request.setValue("ZVPn5Kw7Lsc8o-YUfF", forHTTPHeaderField: "User-Agent")
    
    let task = session.downloadTask(with: request)
    activeDownloads[model.id] = task
    downloadDelegates[model.id] = delegate
    task.resume()
    print("🌐 [ModelDownloader] Download session initialized and task resumed.")
  }

  /// Cancels an in-progress download.
  func cancelDownload(_ model: GemmaModel) {
    print("🛑 [ModelDownloader] Cancelling download: \(model.displayName)")
    activeDownloads[model.id]?.cancel()
    activeDownloads[model.id] = nil
    downloadDelegates[model.id] = nil
    downloadSessions[model.id] = nil
    downloadStatuses[model.id] = .notDownloaded
  }

  /// Deletes a downloaded model.
  func deleteModel(_ model: GemmaModel) {
    print("🗑️ [ModelDownloader] Deleting model: \(model.displayName)")
    let modelDir = Self.modelDirectory(for: model)
    try? FileManager.default.removeItem(at: modelDir)
    downloadStatuses[model.id] = .notDownloaded
  }

  /// Returns the status for a model.
  func status(for model: GemmaModel) -> DownloadStatus {
    return downloadStatuses[model.id] ?? .notDownloaded
  }
}

// MARK: - Download Delegate
private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
  let modelId: String
  let expectedBytes: Int64
  let onProgress: (Double) -> Void
  let onComplete: (URL?, Error?) -> Void
  private var lastProgressTime: CFAbsoluteTime = 0

  init(
    modelId: String,
    expectedBytes: Int64,
    onProgress: @escaping (Double) -> Void,
    onComplete: @escaping (URL?, Error?) -> Void
  ) {
    self.modelId = modelId
    self.expectedBytes = expectedBytes
    self.onProgress = onProgress
    self.onComplete = onComplete
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    print("🌐 [DownloadDelegate] Finished downloading file to temp location: \(location.path)")
    if let response = downloadTask.response as? HTTPURLResponse, response.statusCode != 200 {
      let error = NSError(
        domain: "com.google.Gemma4Chat",
        code: response.statusCode,
        userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP status \(response.statusCode)"]
      )
      onComplete(nil, error)
      return
    }
    
    // Copy file to a safe place synchronously before URLSession deletes it upon method exit
    let safeTempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".litertlm")
    do {
      try FileManager.default.copyItem(at: location, to: safeTempURL)
      print("🌐 [DownloadDelegate] Synchronously copied temp file to safe path: \(safeTempURL.path)")
      onComplete(safeTempURL, nil)
    } catch {
      print("❌ [DownloadDelegate] Failed to synchronously copy temp file: \(error.localizedDescription)")
      onComplete(nil, error)
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    print("🌐 [DownloadDelegate] Bytes: \(totalBytesWritten) of \(totalBytesExpectedToWrite)")
    let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedBytes
    let progress = expected > 0 ? Double(totalBytesWritten) / Double(expected) : 0.0
      
    // Throttle callbacks to at most once every 100ms
    let now = CFAbsoluteTimeGetCurrent()
    if now - lastProgressTime > 0.10 || progress >= 1.0 {
      lastProgressTime = now
      onProgress(progress)
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    if let error = error {
      print("❌ [DownloadDelegate] Task completed with error: \(error.localizedDescription)")
      onComplete(nil, error)
    }
  }
}
