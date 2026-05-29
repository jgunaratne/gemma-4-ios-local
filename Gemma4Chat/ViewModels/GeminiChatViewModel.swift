import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "Gemma4Chat", category: "GeminiChatViewModel")

/// View model for the Gemini cloud chat screen.
/// Follows the same streaming-buffer pattern as ChatViewModel but uses GeminiAPIService
/// and manages conversation history directly (since there's no on-device engine state).
@MainActor
@Observable
class GeminiChatViewModel {
  var messages: [ChatMessage] = []
  var isGenerating = false
  var hasStartedStreaming = false

  private let apiService: GeminiAPIService
  private var inferenceTask: Task<Void, Never>?

  /// Streaming buffer for batching UI updates.
  private static let streamingBufferTimeSeconds = 0.10

  init(apiKey: String, modelId: String = "gemini-3.5-flash", context: String = "") {
    let systemInstruction = context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? nil
      : "The user has provided the following context for this conversation. Use it to inform your responses:\n\n\(context)"
    self.apiService = GeminiAPIService(apiKey: apiKey, modelId: modelId, systemInstruction: systemInstruction)
  }

  /// Send a user message and generate a streaming response.
  func sendMessage(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    // Add user message.
    let userMessage = ChatMessage(side: .user, content: trimmed)
    messages.append(userMessage)

    // Add loading placeholder.
    let loadingMessage = ChatMessage(side: .model, isLoading: true)
    messages.append(loadingMessage)

    isGenerating = true
    hasStartedStreaming = false

    inferenceTask = Task(priority: .high) {
      do {
        // Build conversation history from all non-loading, non-error messages.
        let conversationHistory = messages
          .filter { !$0.isLoading && !$0.content.hasPrefix("⚠️") }
          .compactMap { msg -> (role: String, content: String)? in
            let role = msg.side == .user ? "user" : "model"
            let content = msg.content
            guard !content.isEmpty else { return nil }
            return (role, content)
          }

        let stream = apiService.sendMessageStream(conversationHistory: conversationHistory)

        let startTime = CFAbsoluteTimeGetCurrent()
        var firstTokenTime: Double = -1
        var content = ""
        var decodeTokens = 0
        var lastUpdateTime = CFAbsoluteTimeGetCurrent()
        var partialBuffer = ""
        var currentThinkingContent = ""
        var isInThinkingPhase = false

        for try await (partialResult, partialThinking) in stream {
          try Task.checkCancellation()
          decodeTokens += 1

          if firstTokenTime < 0 {
            firstTokenTime = CFAbsoluteTimeGetCurrent()
            hasStartedStreaming = true
            removeLoadingMessage()
          }

          let hasThinking = partialThinking != nil && !partialThinking!.isEmpty

          if hasThinking {
            currentThinkingContent += partialThinking!
            if !isInThinkingPhase {
              isInThinkingPhase = true
              let thinkingMessage = ChatMessage(
                side: .model, isThinking: true, thinkingContent: currentThinkingContent
              )
              messages.append(thinkingMessage)
            } else {
              if let lastIdx = messages.indices.last, messages[lastIdx].isThinking {
                messages[lastIdx].thinkingContent = currentThinkingContent
                messages = Array(messages)
              }
            }
          } else {
            // Transition from thinking to response.
            if isInThinkingPhase {
              isInThinkingPhase = false
              if let lastIdx = messages.indices.last, messages[lastIdx].isThinking {
                messages[lastIdx].isThinking = false
                messages = Array(messages)
              }
            }

            // Ensure we have a response message.
            let lastMessage = messages.last
            if lastMessage?.side != .model || lastMessage?.isLoading == true
              || lastMessage?.isThinking == true
                || (lastMessage?.thinkingContent.isEmpty == false && lastMessage?.content.isEmpty == true)
            {
              let responseMessage = ChatMessage(side: .model)
              messages.append(responseMessage)
            }

            content += partialResult
            if !partialResult.isEmpty {
              partialBuffer += partialResult
              let now = CFAbsoluteTimeGetCurrent()
              if now - lastUpdateTime > Self.streamingBufferTimeSeconds {
                if let lastIdx = messages.indices.last {
                  messages[lastIdx].content += partialBuffer
                  messages = Array(messages)
                }
                partialBuffer = ""
                lastUpdateTime = now
              }
            }
          }
        }

        // Flush remaining buffer.
        if !partialBuffer.isEmpty {
          if let lastIdx = messages.indices.last {
            messages[lastIdx].content += partialBuffer
            messages = Array(messages)
          }
        }

        // Calculate stats.
        let endTime = CFAbsoluteTimeGetCurrent()
        let ttft = firstTokenTime > 0 ? (firstTokenTime - startTime) * 1000 : 0
        let decodeDuration = firstTokenTime > 0 ? endTime - firstTokenTime : 0
        let decodeSpeed = decodeDuration > 0 ? Double(decodeTokens) / decodeDuration : 0
        let prefillSpeed = ttft > 0 ? 1000.0 / ttft : 0

        let stats = InferenceStats(
          latencyMs: (endTime - startTime) * 1000,
          timeToFirstTokenMs: ttft,
          prefillTokensPerSecond: prefillSpeed,
          decodeTokensPerSecond: decodeSpeed
        )

        if let lastIdx = messages.indices.last, messages[lastIdx].side == .model {
          messages[lastIdx].stats = stats
        }

        hasStartedStreaming = false
        isGenerating = false
        inferenceTask = nil

      } catch is CancellationError {
        print("🛑 [GeminiChatViewModel] Task was cancelled.")
        isGenerating = false
        hasStartedStreaming = false
        inferenceTask = nil
      } catch {
        print("❌ [GeminiChatViewModel] Stream error: \(error.localizedDescription)")
        logger.error("Gemini API error: \(error)")
        removeLoadingMessage()
        addErrorMessage(error.localizedDescription)
        isGenerating = false
        hasStartedStreaming = false
        inferenceTask = nil
      }
    }
  }

  /// Stop the current generation.
  func stopGeneration() {
    inferenceTask?.cancel()
    isGenerating = false
    hasStartedStreaming = false
    inferenceTask = nil
  }

  /// Clear all messages.
  func clearMessages() {
    messages.removeAll()
  }

  private func removeLoadingMessage() {
    if let idx = messages.lastIndex(where: { $0.isLoading }) {
      messages.remove(at: idx)
    }
  }

  private func addErrorMessage(_ text: String) {
    let errorMsg = ChatMessage(side: .model, content: "⚠️ \(text)")
    messages.append(errorMsg)
  }
}
