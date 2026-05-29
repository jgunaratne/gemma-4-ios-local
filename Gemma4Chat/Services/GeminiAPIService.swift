import Foundation
import OSLog

private let logger = Logger(subsystem: "Gemma4Chat", category: "GeminiAPI")

/// Service for calling the Gemini cloud API (e.g., Gemini 3.5 Flash).
class GeminiAPIService {
  private let apiKey: String
  private let modelId: String
  private let systemInstruction: String?

  /// Base URL for the Gemini generative language API.
  private static let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

  init(apiKey: String, modelId: String = "gemini-3.5-flash", systemInstruction: String? = nil) {
    self.apiKey = apiKey
    self.modelId = modelId
    self.systemInstruction = systemInstruction
    logger.info("GeminiAPIService initialized for model: \(modelId), hasContext: \(systemInstruction != nil)")
  }

  /// Stream response tokens given conversation history.
  /// Returns tuples of (responseText, thinkingText?) to match the local inference stream format.
  func sendMessageStream(
    conversationHistory: [(role: String, content: String)]
  ) -> AsyncThrowingStream<(String, String?), Error> {
    AsyncThrowingStream { continuation in
      Task {
        do {
          let urlString =
            "\(Self.baseURL)/\(modelId):streamGenerateContent?alt=sse&key=\(apiKey)"
          guard let url = URL(string: urlString) else {
            throw GeminiAPIError.invalidURL
          }

          print("🌐 [GeminiAPI] POST \(Self.baseURL)/\(modelId):streamGenerateContent")

          var request = URLRequest(url: url)
          request.httpMethod = "POST"
          request.setValue("application/json", forHTTPHeaderField: "Content-Type")

          // Build the request body with conversation history.
          let contents = conversationHistory.map { (role, content) -> [String: Any] in
            [
              "role": role,
              "parts": [["text": content]],
            ]
          }
          var body: [String: Any] = ["contents": contents]
          if let systemInstruction = self.systemInstruction {
            body["systemInstruction"] = [
              "parts": [["text": systemInstruction]]
            ]
          }
          request.httpBody = try JSONSerialization.data(withJSONObject: body)
          print("🌐 [GeminiAPI] Request body: \(String(data: request.httpBody!, encoding: .utf8) ?? "nil")")

          let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

          if let httpResponse = response as? HTTPURLResponse {
            print("🌐 [GeminiAPI] HTTP status: \(httpResponse.statusCode)")
            guard httpResponse.statusCode == 200 else {
              // Try to read the error body.
              var errorBody = ""
              for try await line in asyncBytes.lines {
                errorBody += line
              }
              print("❌ [GeminiAPI] Error response: \(errorBody)")
              logger.error(
                "API returned status \(httpResponse.statusCode): \(errorBody)")
              throw GeminiAPIError.httpError(
                statusCode: httpResponse.statusCode, message: errorBody)
            }
          }

          // Parse SSE stream: each event line starts with "data: " followed by JSON.
          var chunkCount = 0
          for try await line in asyncBytes.lines {
            try Task.checkCancellation()
            if chunkCount == 0 {
              print("🌐 [GeminiAPI] First SSE line received")
            }
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            guard let data = jsonString.data(using: .utf8) else { continue }

            chunkCount += 1
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
            {
              for part in parts {
                if let text = part["text"] as? String {
                  let thought = part["thought"] as? Bool ?? false
                  if thought {
                    continuation.yield(("", text))
                  } else {
                    continuation.yield((text, nil))
                  }
                }
              }
            } else {
              print("⚠️ [GeminiAPI] Could not parse SSE chunk #\(chunkCount): \(jsonString.prefix(200))")
            }
          }

          print("✅ [GeminiAPI] Stream finished. Total chunks: \(chunkCount)")
          continuation.finish()
        } catch {
          logger.error("Gemini API streaming failed: \(error.localizedDescription)")
          continuation.finish(throwing: error)
        }
      }
    }
  }
}

// MARK: - Errors

enum GeminiAPIError: LocalizedError {
  case invalidURL
  case httpError(statusCode: Int, message: String)
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "Invalid API URL."
    case .httpError(let code, let message):
      if code == 400 {
        return "Invalid API key or bad request."
      } else if code == 429 {
        return "Rate limit exceeded. Please try again shortly."
      }
      return "API error (\(code)): \(message)"
    case .invalidResponse:
      return "Could not parse the API response."
    }
  }
}
