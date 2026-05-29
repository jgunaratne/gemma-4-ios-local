import Foundation

/// Represents a downloadable Gemma model.
struct GemmaModel: Identifiable, Hashable {
  let id: String
  let name: String
  let displayName: String
  let sizeDescription: String
  let sizeInBytes: Int64
  let downloadURL: URL
  let info: String
  let learnMoreURL: URL?

  /// Whether to use GPU backend (vs CPU).
  let preferGPU: Bool

  /// Default inference parameters.
  let defaultMaxTokens: Int
  let maxContextLength: Int
  let defaultTopK: Int
  let defaultTopP: Float
  let defaultTemperature: Float

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  static func == (lhs: GemmaModel, rhs: GemmaModel) -> Bool {
    lhs.id == rhs.id
  }
}

// MARK: - Available Models
extension GemmaModel {
  static let gemma4_e2b = GemmaModel(
    id: "gemma-4-e2b-it",
    name: "gemma4_2b_v09_obfus_fix_all_modalities_thinking",
    displayName: "Gemma 4 E2B",
    sizeDescription: "~2.5 GB",
    sizeInBytes: 2_538_766_336,
    downloadURL: URL(
      string: "https://dl.google.com/google-ai-edge-gallery/android/gemma4/20260325/gemma4_2b_v09_obfus_fix_all_modalities_thinking.litertlm"
    )!,
    info: "Gemma 4 E2B is the next-generation compact model with native chain-of-thought reasoning support.",
    learnMoreURL: URL(string: "https://huggingface.co/google"),
    preferGPU: true,
    defaultMaxTokens: 4000,
    maxContextLength: 8192,
    defaultTopK: 64,
    defaultTopP: 0.95,
    defaultTemperature: 1.0
  )

  static let gemma4_e4b = GemmaModel(
    id: "gemma-4-e4b-it",
    name: "gemma4_4b_v09_obfus_fix_all_modalities_thinking",
    displayName: "Gemma 4 E4B",
    sizeDescription: "~3.6 GB",
    sizeInBytes: 3_609_411_584,
    downloadURL: URL(
      string: "https://dl.google.com/google-ai-edge-gallery/android/gemma4/20260325/gemma4_4b_v09_obfus_fix_all_modalities_thinking.litertlm"
    )!,
    info: "Gemma 4 E4B is a powerful, high-performance local model with full reasoning capabilities.",
    learnMoreURL: URL(string: "https://huggingface.co/google"),
    preferGPU: true,
    defaultMaxTokens: 4000,
    maxContextLength: 8192,
    defaultTopK: 64,
    defaultTopP: 0.95,
    defaultTemperature: 1.0
  )

  /// All available models.
  static let allModels: [GemmaModel] = [
    .gemma4_e4b,
    .gemma4_e2b,
  ]
}
