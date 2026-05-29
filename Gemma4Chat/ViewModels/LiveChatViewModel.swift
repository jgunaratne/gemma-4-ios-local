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

  /// Dynamically generated suggested questions to ask Gemini Live.
  var suggestedQuestions: [String] = []
  var isGeneratingQuestions = false

  var sessionStatus: LiveSessionStatus { session.status }

  // MARK: - Services

  let session = GeminiLiveSession()
  let recorder = AudioRecorder()
  let player = AudioPlayer()

  private let apiKey: String
  private let context: String

  // MARK: - Init

  init(apiKey: String, context: String = "", character: String = "", voice: String = "") {
    self.apiKey = apiKey
    self.context = context

    // Match the recommended prebuilt voice name to our GeminiVoice enum
    if let matchedVoice = GeminiVoice.allCases.first(where: { $0.rawValue.lowercased() == voice.lowercased() }) {
      session.voice = matchedVoice
    }

    let trimmedChar = character.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedChar.isEmpty {
      // Override default friendly assistant instruction with the customized persona
      session.systemInstruction = """
      Adopt the following persona/character profile for this entire live voice conversation:
      \(trimmedChar)

      Keep responses natural, conversational, concise, and fully in-character.
      You are speaking with the user in real-time via voice.
      """
    }

    // Append user-provided context to the session's system instruction
    let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedContext.isEmpty {
      session.systemInstruction += "\n\nThe user has provided the following context for this conversation. Use it to inform your responses:\n\n\(trimmedContext)"
    }

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
      guard let self else { return }
      // Resume mic sending now that the model has finished speaking
      self.recorder.isSendingPaused = false
      // isSpeaking will be set to false by the player's onPlaybackFinished
      
      // Generate fresh suggestions based on the new state of the conversation
      self.generateSuggestedQuestions()
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
        
        // Generate initial suggestions immediately on connect
        self.generateSuggestedQuestions()
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

  // MARK: - Suggested Questions Generator

  func generateSuggestedQuestions() {
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let contextText = context.trimmingCharacters(in: .whitespacesAndNewlines)
    
    guard !key.isEmpty, !contextText.isEmpty else { return }
    
    isGeneratingQuestions = true
    
    // Build current chat transcript history
    let history = transcript.map { "\($0.role.rawValue.uppercased()): \($0.text)" }.joined(separator: "\n")
    
    let prompt = """
    You are an expert interview coach and content researcher.
    Your job is to analyze the provided podcast/article context and the current conversation transcript history between the user and Gemini Live, and generate exactly 5 high-quality, specific, engaging follow-up questions that the user could ask Gemini Live next.

    Goal:
    - Provide questions that dive deeper into the most interesting details of the podcast/context.
    - The questions must be relevant to the current stage of the conversation.
    - Keep each question short, punchy, and natural to say out loud (1 sentence max).

    Podcast/Article Context:
    \"\"\"
    \(contextText)
    \"\"\"

    Current Conversation History:
    \"\"\"
    \(history.isEmpty ? "[No turns yet. The conversation is just starting.]" : history)
    \"\"\"

    Output exactly 5 bullet-point questions. Start each question with a dash (-) or bullet point. Do not include introductory or concluding remarks, just output the 3 bullet points.
    """
    
    Task {
      do {
        let response = try await GeminiAPIService.generateContent(apiKey: key, prompt: prompt)
        await MainActor.run {
          // Parse bullet points
          let lines = response.components(separatedBy: .newlines)
          let parsed = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("-") || $0.hasPrefix("•") || $0.hasPrefix("*") }
            .map { String($0.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
            .prefix(5)
          
          if parsed.count >= 2 {
            self.suggestedQuestions = Array(parsed)
          } else {
            // Fallback to line-splitting if prefix doesn't exist
            let cleanLines = lines
              .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
              .filter { !$0.isEmpty }
              .prefix(5)
            self.suggestedQuestions = Array(cleanLines)
          }
          self.isGeneratingQuestions = false
        }
      } catch {
        print("❌ [LiveChatVM] Failed to generate suggested questions: \(error.localizedDescription)")
        await MainActor.run {
          self.isGeneratingQuestions = false
        }
      }
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
