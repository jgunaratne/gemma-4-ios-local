import Foundation

// MARK: - Types

enum LiveSessionStatus: String, Sendable {
  case idle, connecting, connected, reconnecting, error
}

/// Available Gemini Live voices.
enum GeminiVoice: String, CaseIterable, Sendable {
  case puck = "Puck"
  case charon = "Charon"
  case kore = "Kore"
  case fenrir = "Fenrir"
  case aoede = "Aoede"
  case leda = "Leda"
  case orus = "Orus"
  case vale = "Vale"

  var displayName: String { rawValue }
}

// MARK: - GeminiLiveSession

/// Manages a bidirectional WebSocket connection to the Gemini Multimodal Live API.
/// Sends mic audio (PCM 16kHz Int16) and receives model audio (PCM 24kHz Int16).
@Observable
@MainActor
final class GeminiLiveSession {

  private(set) var status: LiveSessionStatus = .idle {
    didSet { onStatusChange?(status) }
  }

  var onTextChunk: (@MainActor (String) -> Void)?
  var onAudioChunk: (@MainActor (Data) -> Void)?
  var onTurnComplete: (@MainActor () -> Void)?
  var onError: (@MainActor (String) -> Void)?
  var onStatusChange: (@MainActor (LiveSessionStatus) -> Void)?
  /// Fires when a model audio turn starts — the first audio chunk of a new turn.
  var onAudioTurnStarted: (@MainActor () -> Void)?

  nonisolated(unsafe) private var webSocketTask: URLSessionWebSocketTask?
  private var session: URLSession?
  private var delegate: LiveSessionDelegate?

  // Ping timer — keeps the connection alive during silent periods.
  private var pingTimer: Timer?
  private static let pingInterval: TimeInterval = 20

  // Reconnect state
  private var reconnectAttempts = 0
  private static let maxReconnectAttempts = 5
  private var lastApiKey: String = ""
  private var reconnectTask: Task<Void, Never>?

  /// Track whether the current model turn has already fired onAudioTurnStarted.
  private var audioTurnStartedForCurrentTurn = false

  /// The voice to use for audio responses. Set before calling connect().
  var voice: GeminiVoice = .puck

  /// System instruction sent during setup.
  var systemInstruction = """
    You are a helpful, friendly AI voice assistant called Gemini.
    Respond naturally and conversationally. Keep responses concise and clear.
    You are speaking with the user in real-time via voice.
    Be warm, engaging, and helpful. If you don't know something, say so honestly.
    """

  // MARK: - Connect / Disconnect

  func connect(apiKey: String) {
    guard status == .idle || status == .error || status == .reconnecting else {
      print("[Session] connect() called while \(status) — ignoring")
      return
    }
    lastApiKey = apiKey
    status = .connecting
    stopPing()

    let urlString =
      "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(apiKey)"
    guard let url = URL(string: urlString) else {
      status = .error
      onError?("Invalid URL")
      return
    }

    let setupMessage = buildSetupJSON()

    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 60
    config.timeoutIntervalForResource = 3600

    let del = LiveSessionDelegate { [weak self] task in
      print("[Session] WebSocket opened, sending setup...")
      task.send(.string(setupMessage)) { error in
        if let error {
          print("[Session] Setup send error: \(error.localizedDescription)")
          Task { @MainActor [weak self] in
            self?.onError?(error.localizedDescription)
            self?.status = .error
          }
        } else {
          print("[Session] Setup sent successfully")
        }
      }
      self?.startReceiving(task)
    } onClose: { [weak self] closeCode in
      Task { @MainActor [weak self] in
        guard let self else { return }
        print("[Session] WebSocket closed: \(closeCode.rawValue)")
        self.stopPing()
        if self.status != .idle && self.status != .reconnecting {
          self.onError?("Connection closed (\(closeCode.rawValue)) — reconnecting…")
          self.scheduleReconnect()
        }
      }
    } onComplete: { [weak self] error in
      if let error {
        Task { @MainActor [weak self] in
          print("[Session] Connection error: \(error.localizedDescription)")
          self?.stopPing()
        }
      }
    }
    self.delegate = del

    session = URLSession(configuration: config, delegate: del, delegateQueue: nil)
    let task = session!.webSocketTask(with: url)
    webSocketTask = task
    let host = url.host ?? "unknown"
    print("[Session] Connecting to \(host)...")
    task.resume()
  }

  func disconnect() {
    reconnectTask?.cancel()
    reconnectTask = nil
    reconnectAttempts = 0
    stopPing()
    webSocketTask?.cancel(with: .goingAway, reason: nil)
    webSocketTask = nil
    session?.invalidateAndCancel()
    session = nil
    delegate = nil
    status = .idle
  }

  // MARK: - Send

  func sendAudio(base64Data: String) {
    guard status == .connected else { return }
    let message: [String: Any] = [
      "realtimeInput": [
        "audio": [
          "data": base64Data,
          "mimeType": "audio/pcm;rate=16000",
        ]
      ]
    ]
    sendJSON(message)
  }

  func sendText(_ text: String) {
    guard status == .connected else { return }
    let message: [String: Any] = [
      "clientContent": [
        "turns": [
          ["role": "user", "parts": [["text": text]]]
        ],
        "turnComplete": true,
      ]
    ]
    sendJSON(message)
  }

  // MARK: - Private

  // MARK: Ping keepalive

  private func startPing() {
    stopPing()
    pingTimer = Timer.scheduledTimer(
      withTimeInterval: Self.pingInterval,
      repeats: true
    ) { [weak self] _ in
      self?.sendPing()
    }
  }

  private func stopPing() {
    pingTimer?.invalidate()
    pingTimer = nil
  }

  private nonisolated func sendPing() {
    webSocketTask?.sendPing { error in
      if let error {
        print("[Session] Ping failed: \(error.localizedDescription)")
      }
    }
  }

  // MARK: Reconnect

  private func scheduleReconnect() {
    guard status != .reconnecting, status != .connecting else {
      print("[Session] Reconnect already in progress — skipping duplicate")
      return
    }
    guard reconnectAttempts < Self.maxReconnectAttempts, !lastApiKey.isEmpty else {
      print("[Session] Max reconnect attempts reached — giving up")
      status = .error
      return
    }
    let delay = pow(2.0, Double(reconnectAttempts))
    reconnectAttempts += 1
    status = .reconnecting
    print(
      "[Session] Reconnecting in \(delay)s (attempt \(reconnectAttempts)/\(Self.maxReconnectAttempts))…"
    )

    reconnectTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      guard !Task.isCancelled, let self else { return }
      await MainActor.run {
        self.webSocketTask?.cancel(with: .goingAway, reason: nil)
        self.webSocketTask = nil
        self.session?.invalidateAndCancel()
        self.session = nil
        self.delegate = nil
        self.connect(apiKey: self.lastApiKey)
      }
    }
  }

  private func buildSetupJSON() -> String {
    let setup: [String: Any] = [
      "setup": [
        "model": "models/gemini-3.1-flash-live-preview",
        "generationConfig": [
          "responseModalities": ["AUDIO"],
          "speechConfig": [
            "voiceConfig": [
              "prebuiltVoiceConfig": ["voiceName": voice.rawValue]
            ]
          ],
        ],
        "systemInstruction": [
          "parts": [["text": systemInstruction]]
        ],
        "realtimeInputConfig": [
          "automaticActivityDetection": [
            "startOfSpeechSensitivity": "START_SENSITIVITY_LOW",
            "endOfSpeechSensitivity": "END_SENSITIVITY_HIGH",
            "silenceDurationMs": 300,
          ]
        ],
      ]
    ]
    let data = try! JSONSerialization.data(withJSONObject: setup)
    return String(data: data, encoding: .utf8)!
  }

  private nonisolated func sendJSON(_ obj: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj),
      let text = String(data: data, encoding: .utf8)
    else { return }
    webSocketTask?.send(.string(text)) { error in
      if let error {
        print("[Session] Send error: \(error.localizedDescription)")
      }
    }
  }

  private nonisolated func startReceiving(_ task: URLSessionWebSocketTask) {
    task.receive { [weak self] result in
      guard let self else { return }
      switch result {
      case .success(let message):
        switch message {
        case .string(let text):
          Task { @MainActor in self.handleMessage(text) }
        case .data(let data):
          if let text = String(data: data, encoding: .utf8) {
            Task { @MainActor in self.handleMessage(text) }
          }
        @unknown default: break
        }
        self.startReceiving(task)
      case .failure(let error):
        Task { @MainActor in
          print("[Session] Receive error: \(error.localizedDescription)")
          self.onError?(error.localizedDescription)
          self.status = .error
        }
      }
    }
  }

  private func handleMessage(_ text: String) {
    guard let data = text.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return }

    // Setup complete
    if json["setupComplete"] != nil {
      print("[Session] Setup complete — connected")
      reconnectAttempts = 0
      status = .connected
      startPing()
      return
    }

    // Server content (audio + text responses)
    if let content = json["serverContent"] as? [String: Any] {
      if let turn = content["modelTurn"] as? [String: Any],
        let parts = turn["parts"] as? [[String: Any]]
      {
        for part in parts {
          if let t = part["text"] as? String {
            onTextChunk?(t)
          }
          if let inline = part["inlineData"] as? [String: Any],
            let mime = inline["mimeType"] as? String,
            let b64 = inline["data"] as? String,
            mime.hasPrefix("audio/")
          {
            // Fire audio turn start on first chunk
            if !audioTurnStartedForCurrentTurn {
              audioTurnStartedForCurrentTurn = true
              onAudioTurnStarted?()
            }
            if let audioData = Data(base64Encoded: b64) {
              onAudioChunk?(audioData)
            }
          }
        }
      }
      if content["turnComplete"] as? Bool == true {
        audioTurnStartedForCurrentTurn = false
        onTurnComplete?()
      }
    }
  }
}

// MARK: - LiveSessionDelegate

private final class LiveSessionDelegate: NSObject, URLSessionWebSocketDelegate {
  let onOpen: (URLSessionWebSocketTask) -> Void
  let onClose: (URLSessionWebSocketTask.CloseCode) -> Void
  let onComplete: (Error?) -> Void

  init(
    onOpen: @escaping (URLSessionWebSocketTask) -> Void,
    onClose: @escaping (URLSessionWebSocketTask.CloseCode) -> Void,
    onComplete: @escaping (Error?) -> Void
  ) {
    self.onOpen = onOpen
    self.onClose = onClose
    self.onComplete = onComplete
  }

  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol protocol: String?
  ) {
    onOpen(webSocketTask)
  }

  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    onClose(closeCode)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    onComplete(error)
  }
}
