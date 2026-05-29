import AVFoundation
import Accelerate

/// Captures microphone input as 16 kHz mono PCM Int16, base64-encoded.
///
/// Approach: capture at the hardware's native format (typically 48 kHz Float32),
/// then manually downsample to 16 kHz and convert to Int16 using Accelerate.
/// This avoids AVAudioConverter's stateful resampling issues when used inside
/// a per-buffer tap callback.
@Observable
@MainActor
final class AudioRecorder {

  /// Current RMS audio level (0…1) for the visualizer.
  private(set) var audioLevel: Float = 0

  /// When true, audio is still captured (for the visualizer) but not sent.
  /// Used to suppress mic input while the model is speaking.
  var isSendingPaused = false

  private var audioEngine: AVAudioEngine?
  private var onDataCallback: ((String) -> Void)?

  /// Target sample rate expected by the Gemini Live API.
  private static let targetSampleRate: Double = 16000

  func start(onData: @escaping (String) -> Void) async throws {
    onDataCallback = onData

    let audioSession = AVAudioSession.sharedInstance()
    // .voiceChat enables Acoustic Echo Cancellation (AEC) — critical
    // for full-duplex voice so the mic doesn't pick up the speaker output.
    try audioSession.setCategory(
      .playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
    try audioSession.setActive(true)

    let engine = AVAudioEngine()
    let inputNode = engine.inputNode
    let hwFormat = inputNode.outputFormat(forBus: 0)
    let hwRate = hwFormat.sampleRate

    guard hwRate > 0 else { throw RecorderError.invalidHardwareFormat }

    // Decimation factor: e.g. 48000 / 16000 = 3
    let decimationFactor = Int(hwRate / Self.targetSampleRate)
    guard decimationFactor >= 1 else { throw RecorderError.invalidHardwareFormat }

    print(
      "[Recorder] Hardware: \(hwFormat.channelCount)ch, \(Int(hwRate))Hz — decimation: \(decimationFactor)x"
    )

    // Pre-allocate a reusable anti-alias filter for decimation.
    // Simple averaging filter with `decimationFactor` taps.
    let filterLength = vDSP_Length(decimationFactor)
    var filterCoeffs = [Float](repeating: 1.0 / Float(decimationFactor), count: decimationFactor)

    inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
      guard let self else { return }

      guard let floatData = buffer.floatChannelData?[0] else { return }
      let frameCount = Int(buffer.frameLength)
      guard frameCount > 0 else { return }

      // ── 1. Compute RMS on raw input for visualizer ─────────────
      var rms: Float = 0
      vDSP_measqv(floatData, 1, &rms, vDSP_Length(frameCount))
      let level = min(sqrt(rms) * 3, 1.0)
      Task { @MainActor in self.audioLevel = level }

      // ── 2. Skip sending if paused (visualizer still updates) ───
      guard !self.isSendingPaused else { return }

      // ── 3. Downsample: hwRate → 16 kHz using decimation ────────
      // For multi-channel input, use only channel 0 (mono).
      let outputFrameCount = frameCount / decimationFactor
      guard outputFrameCount > 0 else { return }

      var downsampled = [Float](repeating: 0, count: outputFrameCount)
      vDSP_desamp(
        floatData,  // input
        vDSP_Stride(decimationFactor),  // decimation factor
        &filterCoeffs,  // FIR anti-alias filter
        &downsampled,  // output
        vDSP_Length(outputFrameCount),  // output length
        filterLength  // filter length
      )

      // ── 4. Float32 → Int16 ─────────────────────────────────────
      // Scale [-1.0, 1.0] → [-32768, 32767]
      var scale: Float = 32767.0
      var scaled = [Float](repeating: 0, count: outputFrameCount)
      vDSP_vsmul(downsampled, 1, &scale, &scaled, 1, vDSP_Length(outputFrameCount))

      var int16Samples = [Int16](repeating: 0, count: outputFrameCount)
      vDSP_vfix16(scaled, 1, &int16Samples, 1, vDSP_Length(outputFrameCount))

      // ── 5. Base64 encode and send ──────────────────────────────
      let data = int16Samples.withUnsafeBufferPointer { ptr in
        Data(buffer: ptr)
      }
      let base64 = data.base64EncodedString()

      self.onDataCallback?(base64)
    }

    engine.prepare()
    try engine.start()
    audioEngine = engine
    print("[Recorder] Started — sending \(Int(Self.targetSampleRate))Hz Int16 mono")
  }

  func stop() {
    audioEngine?.inputNode.removeTap(onBus: 0)
    audioEngine?.stop()
    audioEngine = nil
    onDataCallback = nil
    audioLevel = 0
    print("[Recorder] Stopped")
  }

  enum RecorderError: Error, LocalizedError {
    case invalidHardwareFormat

    var errorDescription: String? {
      switch self {
      case .invalidHardwareFormat: "Could not determine hardware audio format"
      }
    }
  }
}
