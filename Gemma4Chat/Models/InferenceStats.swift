import Foundation

/// Performance statistics from an inference run.
struct InferenceStats {
  /// Total latency in milliseconds.
  let latencyMs: Double
  /// Time to first token in milliseconds.
  let timeToFirstTokenMs: Double
  /// Prefill speed in tokens per second.
  let prefillTokensPerSecond: Double
  /// Decode speed in tokens per second.
  let decodeTokensPerSecond: Double

  /// Human-readable latency string.
  var latencyString: String {
    if latencyMs < 1000 {
      return String(format: "%.0fms", latencyMs)
    } else {
      return String(format: "%.1fs", latencyMs / 1000.0)
    }
  }

  /// Human-readable decode speed.
  var decodeSpeedString: String {
    return String(format: "%.1f tok/s", decodeTokensPerSecond)
  }

  /// Human-readable prefill speed.
  var prefillSpeedString: String {
    return String(format: "%.1f tok/s", prefillTokensPerSecond)
  }

  /// Human-readable time to first token.
  var ttftString: String {
    if timeToFirstTokenMs < 1000 {
      return String(format: "%.0fms", timeToFirstTokenMs)
    } else {
      return String(format: "%.1fs", timeToFirstTokenMs / 1000.0)
    }
  }
}
