import SwiftUI

/// Animated orb visualizer that responds to audio levels.
/// Shows the user's mic input and model's audio output as pulsing concentric rings.
struct AudioVisualizerView: View {
  let inputLevel: Float
  let outputLevel: Float
  let isRecording: Bool
  let isSpeaking: Bool

  // Accent colors
  private static let micColor = Color(hex: "4285F4")
  private static let speakerColor = Color(hex: "9B72CB")

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
      let time = timeline.date.timeIntervalSinceReferenceDate
      Canvas { context, size in
        drawOrb(context: context, size: size, time: time)
      }
    }
    .aspectRatio(1, contentMode: .fit)
  }

  private func drawOrb(context: GraphicsContext, size: CGSize, time: TimeInterval) {
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    let maxRadius = min(size.width, size.height) / 2 * 0.85

    // Determine active state and color
    let isActive = (isRecording && inputLevel > 0.01) || (isSpeaking && outputLevel > 0.01)
    let level = isSpeaking ? CGFloat(outputLevel) : CGFloat(inputLevel)
    let baseColor = isSpeaking ? Self.speakerColor : Self.micColor

    // Draw concentric rings
    let ringCount = 5
    for i in (0..<ringCount).reversed() {
      let ringFraction = CGFloat(i + 1) / CGFloat(ringCount)
      let breathe = sin(time * 2.0 + Double(i) * 0.8) * 0.03

      let dynamicScale: CGFloat
      if isActive {
        dynamicScale = ringFraction * (0.4 + level * 0.6) + CGFloat(breathe)
      } else {
        // Idle gentle pulse
        let idle = sin(time * 1.2 + Double(i) * 0.5) * 0.02
        dynamicScale = ringFraction * 0.3 + CGFloat(idle)
      }

      let radius = maxRadius * max(dynamicScale, 0.05)
      let opacity =
        isActive
        ? (0.12 + Double(ringFraction) * 0.2)
        : (0.04 + Double(ringFraction) * 0.06)

      let rect = CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
      )
      let path = Path(ellipseIn: rect)

      context.fill(
        path,
        with: .color(baseColor.opacity(opacity))
      )
    }

    // Inner glow core
    let coreRadius = maxRadius * (isActive ? (0.12 + level * 0.15) : 0.1)
    let coreRect = CGRect(
      x: center.x - coreRadius,
      y: center.y - coreRadius,
      width: coreRadius * 2,
      height: coreRadius * 2
    )
    context.fill(
      Path(ellipseIn: coreRect),
      with: .color(baseColor.opacity(isActive ? 0.6 : 0.15))
    )
  }
}
