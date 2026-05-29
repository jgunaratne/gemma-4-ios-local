import Foundation

/// Represents a single multiple-choice question in a generated quiz.
struct QuizQuestion: Identifiable, Codable, Equatable {
  var id = UUID()
  let question: String
  let options: [String]
  let correctIndex: Int
  let explanation: String

  enum CodingKeys: String, CodingKey {
    case question
    case options
    case correctIndex
    case explanation
  }
}
