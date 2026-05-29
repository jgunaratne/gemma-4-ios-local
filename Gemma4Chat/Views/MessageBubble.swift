import SwiftUI

struct MessageBubble: View {
  let message: ChatMessage
  @State private var showStats = false
  @State private var dotAnimation = false

  var body: some View {
    VStack(alignment: message.side == .user ? .trailing : .leading, spacing: 4) {
      // Sender label
      HStack(spacing: 4) {
        if message.side == .model {
          Image(systemName: "sparkles")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color(hex: "4285F4"))
        }
        Text(message.side == .user ? "You" : "Gemma")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 4)

      // Message content
      if message.isLoading {
        loadingView
      } else if !message.thinkingContent.isEmpty {
        thinkingView
        if !message.content.isEmpty {
          contentView
        }
      } else {
        contentView
      }

      // Stats row
      if let stats = message.stats, message.side == .model {
        statsRow(stats)
      }
    }
    .frame(maxWidth: .infinity, alignment: message.side == .user ? .trailing : .leading)
  }

  // MARK: - Loading
  private var loadingView: some View {
    HStack(spacing: 6) {
      ForEach(0..<3, id: \.self) { index in
        Circle()
          .fill(Color(hex: "4285F4").opacity(0.6))
          .frame(width: 8, height: 8)
          .scaleEffect(dotAnimation ? 1.3 : 0.7)
          .animation(
            .easeInOut(duration: 0.5)
              .repeatForever(autoreverses: true)
              .delay(Double(index) * 0.15),
            value: dotAnimation
          )
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
    .background(
      RoundedRectangle(cornerRadius: 18)
        .fill(Color(.secondarySystemBackground))
    )
    .onAppear { dotAnimation = true }
  }

  // MARK: - Thinking
  private var thinkingView: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        if message.isThinking {
          ProgressView()
            .controlSize(.small)
        } else {
          Image(systemName: "brain.head.profile")
            .font(.system(size: 12))
            .foregroundStyle(Color(hex: "9B72CB"))
        }
        Text(message.isThinking ? "Thinking…" : "Thought process")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color(hex: "9B72CB"))
      }

      Text(message.thinkingContent)
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
        .lineLimit(message.isThinking ? nil : 4)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(Color(hex: "9B72CB").opacity(0.08))
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(Color(hex: "9B72CB").opacity(0.15), lineWidth: 1)
        )
    )
  }

  // MARK: - Content
  private var contentView: some View {
    let bgColor: Color =
      message.side == .user
      ? Color(hex: "4285F4")
      : Color(.secondarySystemBackground)
    let textColor: Color = message.side == .user ? .white : .primary

    return Text(message.content.isEmpty ? " " : message.content)
      .font(.system(size: 15))
      .foregroundStyle(textColor)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(
        BubbleShape(side: message.side)
          .fill(bgColor)
      )
      .textSelection(.enabled)
      .contextMenu {
        Button {
          UIPasteboard.general.string = message.content
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }
      }
  }

  // MARK: - Stats
  private func statsRow(_ stats: InferenceStats) -> some View {
    HStack(spacing: 12) {
      Label(stats.latencyString, systemImage: "clock")
      Label(stats.decodeSpeedString, systemImage: "bolt")
      Label("TTFT: \(stats.ttftString)", systemImage: "gauge.with.dots.needle.33percent")
    }
    .font(.system(size: 11, weight: .medium, design: .monospaced))
    .foregroundStyle(.secondary)
    .padding(.horizontal, 4)
    .padding(.top, 2)
  }
}

// MARK: - Bubble Shape
struct BubbleShape: Shape {
  let side: ChatSide

  func path(in rect: CGRect) -> Path {
    let radius: CGFloat = 18
    let smallRadius: CGFloat = 4

    if side == .user {
      return RoundedCornerShape(
        topLeft: radius, topRight: smallRadius,
        bottomLeft: radius, bottomRight: radius
      ).path(in: rect)
    } else {
      return RoundedCornerShape(
        topLeft: smallRadius, topRight: radius,
        bottomLeft: radius, bottomRight: radius
      ).path(in: rect)
    }
  }
}

struct RoundedCornerShape: Shape {
  var topLeft: CGFloat = 0
  var topRight: CGFloat = 0
  var bottomLeft: CGFloat = 0
  var bottomRight: CGFloat = 0

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let w = rect.size.width
    let h = rect.size.height

    path.move(to: CGPoint(x: topLeft, y: 0))
    path.addLine(to: CGPoint(x: w - topRight, y: 0))
    path.addArc(
      center: CGPoint(x: w - topRight, y: topRight),
      radius: topRight, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
    path.addLine(to: CGPoint(x: w, y: h - bottomRight))
    path.addArc(
      center: CGPoint(x: w - bottomRight, y: h - bottomRight),
      radius: bottomRight, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
    path.addLine(to: CGPoint(x: bottomLeft, y: h))
    path.addArc(
      center: CGPoint(x: bottomLeft, y: h - bottomLeft),
      radius: bottomLeft, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
    path.addLine(to: CGPoint(x: 0, y: topLeft))
    path.addArc(
      center: CGPoint(x: topLeft, y: topLeft),
      radius: topLeft, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

    return path
  }
}
