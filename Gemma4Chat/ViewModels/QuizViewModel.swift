import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "Gemma4Chat", category: "QuizViewModel")

@MainActor
@Observable
class QuizViewModel {
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

  private let inferenceService: LLMInferenceService
  private var inferenceTask: Task<Void, Never>?

  init(inferenceService: LLMInferenceService) {
    self.inferenceService = inferenceService
  }

  /// Returns the current question.
  var currentQuestion: QuizQuestion? {
    if currentQuestionIndex < questions.count {
      return questions[currentQuestionIndex]
    }
    return nil
  }

  /// Returns all questions count.
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

    status = .generating(progressText: "Reading content & preparing GPU…")
    questions = []
    isStillGenerating = true
    score = 0
    currentQuestionIndex = 0
    selectedOptionIndex = nil
    showExplanation = false
    isFinished = false

    let prompt = """
    You are a quiz generator. Read the SOURCE TEXT and create exactly 5 multiple-choice questions that test understanding of its key concepts.

    ### SOURCE TEXT
    \"\"\"
    \(trimmed)
    \"\"\"

    ### RULES
    - Create exactly 5 questions.
    - Each question must have exactly 4 answer options.
    - "correctIndex" is the 0-based index (0, 1, 2, or 3) of the correct option within the "options" array.
    - Do NOT prefix options with letters or numbers (no "A.", "1)", etc.). Use only the option text.
    - Keep each "explanation" to one short, clear sentence.

    After any reasoning, your final answer MUST be ONLY a single JSON array — no markdown, no code fences, no commentary before or after — exactly matching this shape:
    [
      {
        "question": "What is the capital of France?",
        "options": ["London", "Paris", "Berlin", "Rome"],
        "correctIndex": 1,
        "explanation": "Paris is the capital of France."
      }
    ]
    """

    inferenceTask = Task {
      guard let stream = inferenceService.sendMessage(prompt, extraContext: ["enable_thinking": "true"]) else {
        status = .failed(message: "Could not initiate inference.")
        isStillGenerating = false
        return
      }

      var fullResponse = ""
      var currentThoughts = ""
      do {
        for try await (partialResult, partialThinking) in stream {
          try Task.checkCancellation()
          
          if let thinking = partialThinking, !thinking.isEmpty {
            if currentThoughts.isEmpty {
              print("\n🧠 [QuizViewModel] Gemma 4 started thinking:")
              print("----------------------------------------")
            }
            currentThoughts += thinking
            print(thinking, terminator: "")
            fflush(stdout)
            
            // Create a rolling ticker of the last 50 characters of the model's thoughts
            // Strip markdown syntax (*, `) to keep thoughts clean and highly readable
            let cleanThoughts = currentThoughts
              .replacingOccurrences(of: "\n", with: " ")
              .replacingOccurrences(of: "*", with: "")
              .replacingOccurrences(of: "`", with: "")
              .trimmingCharacters(in: .whitespaces)
            
            let ticker = cleanThoughts.isEmpty ? "Drafting thoughts..." : String(cleanThoughts.suffix(50))
            status = .generating(progressText: "Thinking: \"...\(ticker)\"")
          } else if !partialResult.isEmpty {
            if fullResponse.isEmpty {
              print("\n🚀 [QuizViewModel] Main text stream started! Streaming JSON response:")
              print("----------------------------------------")
            }
            fullResponse += partialResult
            print(partialResult, terminator: "")
            // Force flush standard output so the characters appear in the Xcode console instantly!
            fflush(stdout)
            
            // Update progress string dynamically so the user sees the active compilation ticker!
            status = .generating(progressText: "Compiling questions (\(fullResponse.count) chars received)…")
            // Animate incremental parsing in real-time
            parseIncrementalQuestions(from: fullResponse)
          }
        }
        print("\n----------------------------------------")

        isStillGenerating = false

        // Authoritative parse once the full response is in. The incremental regex
        // parser above is only for the live "drafting" animation; this proper
        // JSONDecoder pass is the source of truth and is far more tolerant of
        // formatting quirks (code fences, smart quotes, trailing commas, etc.).
        // Thinking models sometimes emit the JSON inside the "thought" channel,
        // so fall back to parsing the captured thoughts if the main text yields
        // nothing.
        var parsed = parseQuizJSON(from: fullResponse)
        if parsed.isEmpty {
          parsed = parseQuizJSON(from: currentThoughts)
        }
        mergeQuestions(parsed)

        if questions.isEmpty {
          throw NSError(domain: "Gemma4Chat", code: -1, userInfo: [NSLocalizedDescriptionKey: "Gemma completed but no valid questions could be extracted."])
        }

        print("✅ [QuizViewModel] Quiz successfully generated! Raw JSON response:")
        print("----------------------------------------")
        print(fullResponse)
        print("----------------------------------------")

      } catch is CancellationError {
        status = .idle
        isStillGenerating = false
      } catch {
        logger.error("Quiz generation failed: \(error.localizedDescription)")
        isStillGenerating = false
        if questions.isEmpty {
          status = .failed(message: "Failed to compile the quiz. Let's try again with less text or different content.\nError: \(error.localizedDescription)")
        }
      }
    }
  }

  /// Stop the current generation.
  func stopGeneration() {
    inferenceTask?.cancel()
    inferenceService.cancelInference()
    status = .idle
    isStillGenerating = false
    inferenceTask = nil
  }

  /// Handle option selection.
  func selectOption(index: Int) {
    guard selectedOptionIndex == nil else { return }
    selectedOptionIndex = index
    showExplanation = true

    if let current = currentQuestion, index == current.correctIndex {
      score += 1
    }
  }

  /// Progresses to the next question.
  func nextQuestion() {
    selectedOptionIndex = nil
    showExplanation = false

    if currentQuestionIndex + 1 < questions.count {
      currentQuestionIndex += 1
    } else if !isStillGenerating {
      isFinished = true
    }
  }

  /// Clean/reset the quiz state.
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

  // MARK: - Dynamic Incremental Parsing
  private func parseIncrementalQuestions(from text: String) {
    let nsString = text as NSString
    
    // Match everything between { and }
    let pattern = "\\{([\\s\\S]*?)\\}"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
    
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
    
    for match in matches {
      let block = nsString.substring(with: match.range(at: 1))
      
      // Extract "question" key.
      guard let questionText = extractStringValue(forKey: "question", in: block) else {
        continue
      }
      
      // Prevent duplicate parsing.
      if questions.contains(where: { $0.question == questionText }) {
        continue
      }
      
      // Extract "options" array. Be lenient: accept anything with at least 2
      // options so a slightly off-format question still shows during drafting.
      let options = extractOptionsArray(in: block)
      guard options.count >= 2 else {
        continue
      }

      // Extract "correctIndex", clamping to a valid range.
      let rawIndex = extractIntValue(forKey: "correctIndex", in: block) ?? 0
      let correctIndex = min(max(rawIndex, 0), options.count - 1)

      // Extract "explanation".
      let explanationText = extractStringValue(forKey: "explanation", in: block) ?? "No explanation provided."

      let newQuestion = QuizQuestion(
        question: questionText,
        options: options,
        correctIndex: correctIndex,
        explanation: explanationText
      )

      // Animate addition immediately into the active array
      withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
        questions.append(newQuestion)
      }
    }
  }

  // MARK: - Authoritative JSON Parsing

  /// Robustly parses a quiz out of a raw model response using `JSONDecoder`.
  /// Tolerates markdown code fences, smart quotes, trailing commas and a
  /// `correctIndex` encoded as either a number or a string.
  private func parseQuizJSON(from raw: String) -> [QuizQuestion] {
    let sanitized = sanitizeJSON(raw)
    guard let arrayString = extractJSONArray(from: sanitized),
          let data = arrayString.data(using: .utf8) else {
      return []
    }

    guard let dtos = try? JSONDecoder().decode([QuizQuestionDTO].self, from: data) else {
      return []
    }
    return dtos.compactMap { $0.toQuizQuestion() }
  }

  /// Strips code fences / smart quotes and removes trailing commas so the text
  /// stands a chance of being valid JSON.
  private func sanitizeJSON(_ raw: String) -> String {
    var text = raw
    // Remove markdown code fences such as ```json ... ```
    text = text.replacingOccurrences(
      of: "```[a-zA-Z]*", with: "", options: .regularExpression)
    text = text.replacingOccurrences(of: "```", with: "")
    // Normalize curly/smart quotes to straight quotes.
    let replacements: [String: String] = [
      "\u{201C}": "\"", "\u{201D}": "\"", "\u{2018}": "'", "\u{2019}": "'",
    ]
    for (from, to) in replacements {
      text = text.replacingOccurrences(of: from, with: to)
    }
    // Remove trailing commas before a closing ] or } (e.g. `"d"],` -> `"d"]`).
    text = text.replacingOccurrences(
      of: ",\\s*([\\]}])", with: "$1", options: .regularExpression)
    return text
  }

  /// Extracts the outermost JSON array substring (first `[` to the matching
  /// last `]`) from arbitrary surrounding text.
  private func extractJSONArray(from text: String) -> String? {
    guard let start = text.firstIndex(of: "["),
          let end = text.lastIndex(of: "]"),
          start < end else {
      return nil
    }
    return String(text[start...end])
  }

  /// Merges `newQuestions` into the live list, preserving any already displayed
  /// during drafting and appending only ones not yet present (matched by question
  /// text) so the active quiz isn't disrupted mid-answer.
  private func mergeQuestions(_ newQuestions: [QuizQuestion]) {
    for question in newQuestions {
      if !questions.contains(where: { $0.question == question.question }) {
        questions.append(question)
      }
    }
  }

  // MARK: - Helper String Scanners
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
      let rawVal = nsString.substring(with: match.range(at: 1))
      return Int(rawVal)
    }
    return nil
  }

  private func extractOptionsArray(in block: String) -> [String] {
    let pattern = "\"options\"\\s*:\\s*\\[([\\s\\S]*?)\\]"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    
    let nsString = block as NSString
    guard let match = regex.firstMatch(in: block, range: NSRange(location: 0, length: nsString.length)) else {
      return []
    }
    
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

// MARK: - Lenient Decoding

/// A `correctIndex` value that may arrive from the model as either a JSON
/// number (`1`) or a JSON string (`"1"`).
private struct FlexibleInt: Decodable {
  let value: Int

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let intValue = try? container.decode(Int.self) {
      value = intValue
    } else if let stringValue = try? container.decode(String.self),
              let parsed = Int(stringValue.trimmingCharacters(in: .whitespaces)) {
      value = parsed
    } else {
      value = 0
    }
  }
}

/// Tolerant decoding shape for a single quiz question. Maps to `QuizQuestion`
/// after validation/clamping so malformed-but-recoverable entries still work.
private struct QuizQuestionDTO: Decodable {
  let question: String
  let options: [String]
  let correctIndex: FlexibleInt?
  let explanation: String?

  func toQuizQuestion() -> QuizQuestion? {
    let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuestion.isEmpty, options.count >= 2 else { return nil }

    let rawIndex = correctIndex?.value ?? 0
    let clampedIndex = min(max(rawIndex, 0), options.count - 1)

    let explanationText = (explanation?.isEmpty == false) ? explanation! : "No explanation provided."

    return QuizQuestion(
      question: trimmedQuestion,
      options: options,
      correctIndex: clampedIndex,
      explanation: explanationText
    )
  }
}
