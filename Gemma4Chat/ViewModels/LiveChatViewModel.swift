import SwiftUI

/// Central ViewModel for the Gemini Live voice chat.
/// Owns the session, audio recorder, audio player, and conversation transcript.
@Observable
@MainActor
final class LiveChatViewModel {

  // MARK: - State

  /// Whether the mic is currently capturing and sending audio.
  var isRecording = false

  /// Whether the mic is muted (user chose to mute while staying connected).
  var isMuted = false

  /// Whether the model is currently speaking (audio playing back).
  var isSpeaking = false

  /// Conversation transcript shown in the UI.
  var transcript: [LiveTranscriptEntry] = []

  var sessionStatus: LiveSessionStatus { session.status }

  // MARK: - Services

  let session = GeminiLiveSession()
  let recorder = AudioRecorder()
  let player = AudioPlayer()

  private let apiKey: String

  // MARK: - Init

  init(apiKey: String) {
    self.apiKey = apiKey
    wireCallbacks()
  }

  // MARK: - Connect / Disconnect

  func connect() {
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
      addTranscript(.system, "Please enter your Gemini API key in Settings")
      return
    }
    session.connect(apiKey: key)
  }

  func disconnect() {
    stopRecording()
    player.stop()
    session.disconnect()
    isSpeaking = false
  }

  // MARK: - Mic Control

  /// Toggle mic mute/unmute while staying connected.
  func toggleMute() async {
    guard session.status == .connected else { return }
    if isRecording {
      muteMic()
    } else {
      await unmuteMic()
    }
  }

  /// Start capturing mic audio and sending to Gemini.
  func unmuteMic() async {
    guard session.status == .connected, !isRecording else { return }
    isMuted = false
    isRecording = true
    do {
      try await recorder.start { [weak self] base64 in
        self?.session.sendAudio(base64Data: base64)
      }
    } catch {
      addTranscript(.error, "Mic error: \(error.localizedDescription)")
      isRecording = false
      isMuted = true
    }
  }

  /// Stop mic capture but stay connected.
  func muteMic() {
    recorder.stop()
    isRecording = false
    isMuted = true
  }

  private func stopRecording() {
    recorder.stop()
    isRecording = false
  }

  // MARK: - Text Input

  func sendText(_ text: String) {
    guard !text.isEmpty, session.status == .connected else { return }
    addTranscript(.user, text)
    session.sendText(text)
  }

  // MARK: - Callbacks

  private func wireCallbacks() {
    session.onTextChunk = { [weak self] text in
      self?.addTranscript(.assistant, text)
    }

    session.onAudioChunk = { [weak self] data in
      self?.player.scheduleAudio(data)
    }

    session.onAudioTurnStarted = { [weak self] in
      self?.isSpeaking = true
      // Pause mic sending while model speaks — prevents background noise
      // and speaker→mic feedback from triggering false barge-ins.
      self?.recorder.isSendingPaused = true
    }

    session.onTurnComplete = { [weak self] in
      // Resume mic sending now that the model has finished speaking
      self?.recorder.isSendingPaused = false
      // isSpeaking will be set to false by the player's onPlaybackFinished
    }

    session.onError = { [weak self] error in
      guard let self else { return }
      // Suppress transient socket errors when the session is already
      // reconnecting — the user sees "reconnecting…" from onStatusChange.
      if self.session.status == .reconnecting || self.session.status == .connecting {
        print("[LiveChatVM] Suppressed transient error: \(error)")
        return
      }
      self.addTranscript(.error, error)
    }

    session.onStatusChange = { [weak self] status in
      guard let self else { return }
      switch status {
      case .connected:
        addTranscript(.system, "Connected to Gemini Live")
        // Auto-start mic on connect (unmuted by default)
        Task {
          await self.unmuteMic()
        }
        // Start the audio player engine
        do {
          try player.start()
        } catch {
          addTranscript(.error, "Audio player error: \(error.localizedDescription)")
        }
      case .reconnecting:
        addTranscript(.system, "Connection lost — reconnecting…")
        player.flush()
        isSpeaking = false
      case .idle:
        stopRecording()
        player.stop()
        isSpeaking = false
      case .error:
        stopRecording()
        player.stop()
        isSpeaking = false
      case .connecting:
        break
      }
    }

    player.onPlaybackFinished = { [weak self] in
      self?.isSpeaking = false
    }
  }

  // MARK: - Transcript

  func addTranscript(_ role: LiveTranscriptEntry.Role, _ text: String) {
    // If the last entry is from the same role, append to it (streaming text)
    if let last = transcript.last, last.role == role, role == .assistant {
      transcript[transcript.count - 1].text += text
    } else {
      transcript.append(LiveTranscriptEntry(role: role, text: text))
    }
    // Keep manageable
    if transcript.count > 200 {
      transcript.removeFirst(transcript.count - 150)
    }
  }
}

// MARK: - LiveTranscriptEntry

struct LiveTranscriptEntry: Identifiable {
  let id = UUID()
  var role: Role
  var text: String
  let timestamp = Date()

  enum Role: String {
    case user, assistant, system, error
  }
}
