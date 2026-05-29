import Foundation
import OSLog

private let logger = Logger(subsystem: "com.google.Gemma4Chat", category: "LLMInference")

/// Initialization status for the LLM engine.
enum EngineStatus: Equatable {
  case idle
  case initializing
  case ready
  case failed(message: String)
}

/// Service that manages LiteRTLM engine lifecycle and inference.
/// Mirrors the AiChatModelHelperV2 pattern from the AI Edge Gallery reference app.
@MainActor
@Observable
class LLMInferenceService {
  private(set) var engineStatus: EngineStatus = .idle
  private var engine: Engine?
  private var conversation: Conversation?
  private var currentModel: GemmaModel?

  /// Initialize the engine with a model.
  func initializeEngine(model: GemmaModel, systemPrompt: String = "", temperature: Float? = nil, forceCPU: Bool = false) async {
    engineStatus = .initializing

    do {
      // Clean up previous engine.
      conversation = nil
      engine = nil

      // Opt into experimental APIs (matches reference app pattern).
      ExperimentalFlags.optIntoExperimentalAPIs()
      ExperimentalFlags.enableBenchmark = false

      // Create engine config. Force CPU delegate if requested to bypass Metal GPU shader bugs.
      let backend: Backend = (model.preferGPU && !forceCPU) ? .gpu : .cpu(threadCount: 4)
      let modelPath = ModelDownloader.modelPath(for: model)

      let engineConfig = try EngineConfig(
        modelPath: modelPath,
        backend: backend,
        maxNumTokens: model.maxContextLength
      )

      // Create and initialize engine.
      let newEngine = Engine(engineConfig: engineConfig)
      try await newEngine.initialize()

      // Create conversation config.
      let systemMessage = systemPrompt.isEmpty ? nil : Message(systemPrompt)
      let temp = temperature ?? model.defaultTemperature
      let samplerConfig = try SamplerConfig(
        topK: model.defaultTopK,
        topP: model.defaultTopP,
        temperature: temp
      )

      let conversationConfig = ConversationConfig(
        systemMessage: systemMessage,
        samplerConfig: samplerConfig
      )

      // Create conversation.
      let newConversation = try await newEngine.createConversation(with: conversationConfig)

      self.engine = newEngine
      self.conversation = newConversation
      self.currentModel = model
      self.engineStatus = .ready

      logger.info("Engine initialized for \(model.name)")
    } catch {
      logger.error("Failed to initialize engine: \(error)")
      self.engineStatus = .failed(message: error.localizedDescription)
    }
  }

  /// Send a message and get a streaming response.
  /// Returns tuples of (responseText, thinkingText?) matching the reference app's stream format.
  func sendMessage(_ text: String, extraContext: [String: Any]? = nil) -> AsyncThrowingStream<(String, String?), Error>? {
    guard let conversation = conversation else {
      logger.error("No active conversation")
      return nil
    }

    let message = Message(text)
    let stream = conversation.sendMessageStream(message, extraContext: extraContext)

    return AsyncThrowingStream { continuation in
      Task {
        do {
          for try await responseMessage in stream {
            continuation.yield((responseMessage.toString, responseMessage.channels["thought"]))
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  func resetConversation(systemPrompt: String = "", temperature: Float? = nil) async {
    guard let engine = engine, let model = currentModel else { return }

    do {
      // Nil out conversation first (matches reference app deinit pattern).
      conversation = nil

      let systemMessage = systemPrompt.isEmpty ? nil : Message(systemPrompt)
      let temp = temperature ?? model.defaultTemperature
      let samplerConfig = try SamplerConfig(
        topK: model.defaultTopK,
        topP: model.defaultTopP,
        temperature: temp
      )

      let conversationConfig = ConversationConfig(
        systemMessage: systemMessage,
        samplerConfig: samplerConfig
      )

      conversation = try await engine.createConversation(with: conversationConfig)
      logger.info("Conversation reset")
    } catch {
      logger.error("Failed to reset conversation: \(error)")
    }
  }

  /// Cancel ongoing inference.
  func cancelInference() {
    do {
      try conversation?.cancel()
    } catch {
      logger.error("Failed to cancel inference: \(error)")
    }
  }

  /// Clean up the engine entirely.
  func cleanup() {
    // Release conversation before engine to prevent crashes (b/465752643).
    conversation = nil
    engine = nil
    currentModel = nil
    engineStatus = .idle
  }
}
