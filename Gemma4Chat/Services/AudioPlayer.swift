import AVFoundation
import Accelerate

/// Plays back audio data received from the Gemini Live API.
///
/// The Live API returns audio as 24 kHz mono Int16 PCM. We convert to
/// the engine's native hardware sample rate (typically 48 kHz) Float32
/// before scheduling.
@Observable
@MainActor
final class AudioPlayer {

  /// Current playback level (0…1) for the output visualizer.
  private(set) var outputLevel: Float = 0

  /// Gain boost applied to decoded PCM samples. .voiceChat mode reduces
  /// output volume for echo cancellation; this compensates.
  private static let outputGain: Float = 2.5

  private var audioEngine: AVAudioEngine?
  private var playerNode: AVAudioPlayerNode?

  /// The format used for the player chain (hardware rate, Float32, mono).
  private var chainFormat: AVAudioFormat?

  /// Converts incoming 24 kHz Int16 PCM → hardware-rate Float32.
  private var audioConverter: AVAudioConverter?

  /// Source format for the converter (24 kHz Float32 mono).
  private var sourceFormat: AVAudioFormat?

  // The Gemini Live API returns 24 kHz mono Int16 PCM by default.
  private static let inputSampleRate: Double = 24000
  private static let channels: AVAudioChannelCount = 1

  /// Number of scheduled buffers currently in-flight.
  private var scheduledBufferCount = 0

  /// Called on MainActor when the last scheduled buffer finishes playing.
  var onPlaybackFinished: (@MainActor () -> Void)?

  func start() throws {
    // ── Audio session ───────────────────────────────────────────────
    let audioSession = AVAudioSession.sharedInstance()
    try audioSession.setCategory(
      .playAndRecord, mode: .voiceChat,
      options: [.defaultToSpeaker, .allowBluetoothHFP])
    try audioSession.setActive(true)
    // Force the loudspeaker — .defaultToSpeaker alone doesn't always
    // override .voiceChat's preference for the ear speaker.
    try audioSession.overrideOutputAudioPort(.speaker)

    let engine = AVAudioEngine()
    let node = AVAudioPlayerNode()

    // ── Determine hardware sample rate ─────────────────────────────
    let hardwareRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
    print("[AudioPlayer] Hardware sample rate: \(hardwareRate) Hz")

    guard
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: hardwareRate,
        channels: Self.channels,
        interleaved: false
      )
    else { throw PlayerError.formatError }

    // Source format for the converter: 24 kHz Float32 mono
    guard
      let srcFmt = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Self.inputSampleRate,
        channels: Self.channels,
        interleaved: false
      )
    else { throw PlayerError.formatError }

    // Converter: 24 kHz → hardware rate
    guard let converter = AVAudioConverter(from: srcFmt, to: format) else {
      throw PlayerError.converterError
    }

    // ── Wire the chain ──────────────────────────────────────────────
    engine.attach(node)
    engine.connect(node, to: engine.mainMixerNode, format: format)

    // Output level tap for the visualiser
    let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
    engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: mixerFormat) {
      [weak self] buffer, _ in
      guard let self else { return }
      let level = Self.computeRMS(buffer: buffer)
      Task { @MainActor in self.outputLevel = level }
    }

    engine.prepare()
    try engine.start()
    node.play()

    // Boost mixer output — helps counteract .voiceChat volume reduction
    engine.mainMixerNode.outputVolume = 1.5

    audioEngine = engine
    playerNode = node
    chainFormat = format
    sourceFormat = srcFmt
    audioConverter = converter

    print("[AudioPlayer] Engine started — gain: \(Self.outputGain)x, mixerVol: 1.5")
  }

  func stop() {
    playerNode?.stop()
    audioEngine?.mainMixerNode.removeTap(onBus: 0)
    audioEngine?.stop()
    audioEngine = nil
    playerNode = nil
    chainFormat = nil
    sourceFormat = nil
    audioConverter = nil
    outputLevel = 0
    scheduledBufferCount = 0
  }

  /// Cancel any in-flight playback (e.g. on barge-in).
  func flush() {
    playerNode?.stop()
    playerNode?.play()
    scheduledBufferCount = 0
    outputLevel = 0
  }

  /// Schedule a chunk of raw 24 kHz Int16 PCM audio data for playback.
  /// Converts Int16 → Float32 and resamples 24 kHz → hardware rate.
  func scheduleAudio(_ data: Data) {
    guard let node = playerNode,
      let converter = audioConverter,
      let srcFmt = sourceFormat,
      let dstFmt = chainFormat
    else { return }

    let sampleCount = data.count / MemoryLayout<Int16>.size
    guard sampleCount > 0 else { return }

    // Step 1: Int16 → Float32 at 24 kHz
    let srcFrameCount = AVAudioFrameCount(sampleCount)
    guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFmt, frameCapacity: srcFrameCount)
    else { return }
    srcBuffer.frameLength = srcFrameCount

    data.withUnsafeBytes { rawBuf in
      guard let src = rawBuf.bindMemory(to: Int16.self).baseAddress,
        let dst = srcBuffer.floatChannelData?[0]
      else { return }
      // Convert Int16 → Float32
      for i in 0..<sampleCount {
        dst[i] = Float(src[i]) / 32768.0
      }
      // Apply gain boost and clip to [-1.0, 1.0]
      var gain = Self.outputGain
      vDSP_vsmul(dst, 1, &gain, dst, 1, vDSP_Length(sampleCount))
      var lo: Float = -1.0
      var hi: Float = 1.0
      vDSP_vclip(dst, 1, &lo, &hi, dst, 1, vDSP_Length(sampleCount))
    }

    // Step 2: Resample 24 kHz → hardware rate
    let ratio = dstFmt.sampleRate / srcFmt.sampleRate
    let dstFrameCount = AVAudioFrameCount(Double(srcFrameCount) * ratio)
    guard dstFrameCount > 0,
      let dstBuffer = AVAudioPCMBuffer(pcmFormat: dstFmt, frameCapacity: dstFrameCount)
    else { return }

    var error: NSError?
    let status = converter.convert(to: dstBuffer, error: &error) { _, outStatus in
      outStatus.pointee = .haveData
      return srcBuffer
    }

    guard status != .error, error == nil else {
      print("[AudioPlayer] Conversion error: \(error?.localizedDescription ?? "unknown")")
      return
    }

    // Step 3: Schedule the resampled buffer
    scheduledBufferCount += 1
    node.scheduleBuffer(dstBuffer) { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.scheduledBufferCount -= 1
        if self.scheduledBufferCount <= 0 {
          self.scheduledBufferCount = 0
          self.onPlaybackFinished?()
        }
      }
    }
  }

  // MARK: - Helpers

  private static func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
    guard let channelData = buffer.floatChannelData else { return 0 }
    let count = Int(buffer.frameLength)
    guard count > 0 else { return 0 }
    var rms: Float = 0
    vDSP_measqv(channelData[0], 1, &rms, vDSP_Length(count))
    return min(sqrt(rms) * 5, 1.0)
  }

  enum PlayerError: Error {
    case formatError
    case converterError
  }
}
