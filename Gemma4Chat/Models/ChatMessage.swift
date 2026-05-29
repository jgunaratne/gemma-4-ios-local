import Foundation
import SwiftUI

/// Represents which side of the conversation a message belongs to.
enum ChatSide {
  case user, model
}

/// A single chat message.
@Observable
class ChatMessage: Identifiable, Equatable {
  var id = UUID()
  let side: ChatSide
  var content: String
  var isLoading: Bool
  var isThinking: Bool
  var thinkingContent: String
  var stats: InferenceStats?

  init(
    side: ChatSide,
    content: String = "",
    isLoading: Bool = false,
    isThinking: Bool = false,
    thinkingContent: String = ""
  ) {
    self.side = side
    self.content = content
    self.isLoading = isLoading
    self.isThinking = isThinking
    self.thinkingContent = thinkingContent
  }

  static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
    lhs.id == rhs.id && lhs.content == rhs.content && lhs.isLoading == rhs.isLoading
      && lhs.isThinking == rhs.isThinking && lhs.thinkingContent == rhs.thinkingContent
  }
}
