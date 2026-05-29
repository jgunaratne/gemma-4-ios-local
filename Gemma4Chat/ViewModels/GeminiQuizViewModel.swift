import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "Gemma4Chat", category: "GeminiQuizViewModel")

/// View model for the quiz screen using Gemini cloud API.
/// Mirrors the QuizViewModel pattern but uses GeminiAPIService.
@MainActor
@Observable
class GeminiQuizViewModel {
  enum GenerationStatus: Equatable {
    case idle
    case generating(progressText: String)
    case failed(message: String)
  }

  var status: GenerationStatus = .idle
  var questions: [QuizQuestion] = []
  var isStillGenerating = false

  var currentQuestionIndex = 0
  var selectedOptionIndex: Int? = nil
  var showExplanation = false
  var score = 0
  var isFinished = false

  private let apiService: GeminiAPIService
  private var inferenceTask: Task<Void, Never>?

  init(apiKey: String, modelId: String = "gemini-3.5-flash") {
    self.apiService = GeminiAPIService(apiKey: apiKey, modelId: modelId)
  }

  var currentQuestion: QuizQuestion? {
    if currentQuestionIndex < questions.count {
      return questions[currentQuestionIndex]
    }
    return nil
  }

  var totalQuestionsCount: Int {
    questions.count
  }

  /// Starts generating a quiz from a user-provided source text block.
  func generateQuiz(from text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      status = .failed(message: "Please paste some content first.")
      return
    }

    status = .generating(progressText: "Sending to Gemini 3.5 Flash…")
    questions = []
    isStillGenerating = true
    score = 0
    currentQuestionIndex = 0
    selectedOptionIndex = nil
    showExplanation = false
    isFinished = false

    let prompt = """
    Analyze the source text, think through the key concepts and educational points, and compile exactly a 5-question multiple-choice quiz based on its contents.
    
    ### SOURCE TEXT:
    \"\"\"
    \(trimmed)
    \"\"\"
    
    ### INSTRUCTIONS:
    - First, use your thinking phase to outline the questions, verify the correct options, and plan the explanations.
    - Keep explanations strictly to one clear, short sentence.
    - Then, output your final quiz as a valid, parsable JSON array of objects in the main text block.
    - Each object in the array must have EXACTLY these keys: "question", "options", "correctIndex", and "explanation". 
    - Do NOT prefix option strings with letters (like A, B, C, D). Render only the option text itself.
    
    Strictly follow this JSON structure format:
    [
      {
        "question": "What is the capital of France?",
        "options": ["London", "Paris", "Berlin", "Rome"],
        "correctIndex": 1,
        "explanation": "Paris is the capital of France."
      }
    ]
    """

    let conversationHistory: [(role: String, content: String)] = [("user", prompt)]

    inferenceTask = Task {
      let stream = apiService.sendMessageStream(conversationHistory: conversationHistory)

      var fullResponse = ""
      var currentThoughts = ""
      do {
        for try await (partialResult, partialThinking) in stream {
          try Task.checkCancellation()

          if let thinking = partialThinking, !thinking.isEmpty {
            if currentThoughts.isEmpty {
              print("\n🧠 [GeminiQuizVM] Started thinking:")
              print("----------------------------------------")
            }
            currentThoughts += thinking
            print(thinking, terminator: "")
            fflush(stdout)

            let cleanThoughts = currentThoughts
              .replacingOccurrences(of: "\n", with: " ")
              .replacingOccurrences(of: "*", with: "")
              .replacingOccurrences(of: "`", with: "")
              .trimmingCharacters(in: .whitespaces)

            let ticker = cleanThoughts.isEmpty ? "Drafting thoughts..." : String(cleanThoughts.suffix(50))
            status = .generating(progressText: "Thinking: \"...\(ticker)\"")
          } else if !partialResult.isEmpty {
            if fullResponse.isEmpty {
              print("\n🚀 [GeminiQuizVM] Main text stream started!")
              print("----------------------------------------")
            }
            fullResponse += partialResult
            print(partialResult, terminator: "")
            fflush(stdout)

            status = .generating(progressText: "Compiling questions (\(fullResponse.count) chars received)…")
            parseIncrementalQuestions(from: fullResponse)
          }
        }
        print("\n----------------------------------------")

        isStillGenerating = false
        if questions.isEmpty {
          throw NSError(domain: "Gemma4Chat", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid questions could be extracted from the response."])
        }

        print("✅ [GeminiQuizVM] Quiz generated! \(questions.count) questions")

      } catch is CancellationError {
        status = .idle
        isStillGenerating = false
      } catch {
        logger.error("Quiz generation failed: \(error.localizedDescription)")
        isStillGenerating = false
        if questions.isEmpty {
          status = .failed(message: "Failed to compile the quiz. Try again with less text or different content.\nError: \(error.localizedDescription)")
        }
      }
    }
  }

  func stopGeneration() {
    inferenceTask?.cancel()
    status = .idle
    isStillGenerating = false
    inferenceTask = nil
  }

  func selectOption(index: Int) {
    guard selectedOptionIndex == nil else { return }
    selectedOptionIndex = index
    showExplanation = true

    if let current = currentQuestion, index == current.correctIndex {
      score += 1
    }
  }

  func nextQuestion() {
    selectedOptionIndex = nil
    showExplanation = false

    if currentQuestionIndex + 1 < questions.count {
      currentQuestionIndex += 1
    } else if !isStillGenerating {
      isFinished = true
    }
  }

  func reset() {
    status = .idle
    questions = []
    isStillGenerating = false
    currentQuestionIndex = 0
    selectedOptionIndex = nil
    showExplanation = false
    score = 0
    isFinished = false
    inferenceTask = nil
  }

  // MARK: - Dynamic Incremental Parsing (same as QuizViewModel)

  private func parseIncrementalQuestions(from text: String) {
    let nsString = text as NSString
    let pattern = "\\{([\\s\\S]*?)\\}"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

    let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))

    for match in matches {
      let block = nsString.substring(with: match.range(at: 1))

      guard let questionText = extractStringValue(forKey: "question", in: block) else { continue }
      if questions.contains(where: { $0.question == questionText }) { continue }

      let options = extractOptionsArray(in: block)
      guard options.count == 4 else { continue }

      guard let correctIndex = extractIntValue(forKey: "correctIndex", in: block) else { continue }

      let explanationText = extractStringValue(forKey: "explanation", in: block) ?? "No explanation provided."

      let newQuestion = QuizQuestion(
        question: questionText,
        options: options,
        correctIndex: correctIndex,
        explanation: explanationText
      )

      withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
        questions.append(newQuestion)
      }
    }
  }

  private func extractStringValue(forKey key: String, in block: String) -> String? {
    let pattern = "\"\(key)\"\\s*:\\s*\"([^\"]*)\""
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let nsString = block as NSString
    if let match = regex.firstMatch(in: block, range: NSRange(location: 0, length: nsString.length)) {
      return nsString.substring(with: match.range(at: 1))
        .replacingOccurrences(of: "\\\"", with: "\"")
    }
    return nil
  }

  private func extractIntValue(forKey key: String, in block: String) -> Int? {
    let pattern = "\"\(key)\"\\s*:\\s*(\\d+)"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let nsString = block as NSString
    if let match = regex.firstMatch(in: block, range: NSRange(location: 0, length: nsString.length)) {
      return Int(nsString.substring(with: match.range(at: 1)))
    }
    return nil
  }

  private func extractOptionsArray(in block: String) -> [String] {
    let pattern = "\"options\"\\s*:\\s*\\[([\\s\\S]*?)\\]"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let nsString = block as NSString
    guard let match = regex.firstMatch(in: block, range: NSRange(location: 0, length: nsString.length)) else { return [] }
    let arrayContent = nsString.substring(with: match.range(at: 1))
    let stringPattern = "\"([^\"]*)\""
    guard let stringRegex = try? NSRegularExpression(pattern: stringPattern) else { return [] }
    let nsArrayString = arrayContent as NSString
    let stringMatches = stringRegex.matches(in: arrayContent, range: NSRange(location: 0, length: nsArrayString.length))
    return stringMatches.map {
      nsArrayString.substring(with: $0.range(at: 1))
        .replacingOccurrences(of: "\\\"", with: "\"")
    }
  }
}
