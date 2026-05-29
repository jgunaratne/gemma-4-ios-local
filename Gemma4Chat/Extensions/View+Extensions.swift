import SwiftUI

extension View {
  /// Applies a premium pulsing animation to any SwiftUI View.
  func pulseEffect() -> some View {
    modifier(PulseEffectModifier())
  }
}

struct PulseEffectModifier: SwiftUI.ViewModifier {
  @State private var isPulsing = false

  func body(content: Self.Content) -> some SwiftUI.View {
    content
      .opacity(isPulsing ? 0.45 : 1.0)
      .animation(
        Animation.easeInOut(duration: 1.2)
          .repeatForever(autoreverses: true),
        value: isPulsing
      )
      .onAppear {
        isPulsing = true
      }
  }
}
