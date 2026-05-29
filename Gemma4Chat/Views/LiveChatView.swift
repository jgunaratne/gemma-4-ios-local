import SwiftUI

/// Voice chat view for Gemini Live 3.1 — bidirectional audio streaming.
///
/// Layout:
///   - Top: header with back button, model name, status
///   - Center: animated audio orb visualizer
///   - Middle: transcript of the conversation
///   - Bottom: mic/connect controls + optional text input
struct LiveChatView: View {
  @Bindable var viewModel: LiveChatViewModel
  let onBack: () -> Void

  @State private var textInput = ""
  @State private var showTextInput = false
  @FocusState private var isTextFieldFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      // Header
      chatHeader

      // Main content
      VStack(spacing: 0) {
        // Orb visualizer — hero element
        orbSection

        Divider()
          .padding(.horizontal, 20)

        // Transcript area
        transcriptArea
          .frame(maxHeight: .infinity)

        // Optional text input
        if showTextInput {
          textInputBar
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        Divider()

        // Controls
        controlsBar
      }
    }
    .background(
      LinearGradient(
        colors: [
          Color(.systemBackground),
          Color(hex: "4285F4").opacity(0.02),
          Color(hex: "9B72CB").opacity(0.03),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    )
    .navigationBarHidden(true)
    .onAppear {
      viewModel.connect()
    }
    .onDisappear {
      viewModel.disconnect()
    }
  }

  // MARK: - Header

  private var chatHeader: some View {
    HStack {
      Button {
        viewModel.disconnect()
        onBack()
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.primary)
      }
      .frame(width: 44, height: 44)

      Spacer()

      VStack(spacing: 2) {
        Text("Gemini Live 3.1")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.primary)

        HStack(spacing: 4) {
          Circle()
            .fill(statusDotColor)
            .frame(width: 6, height: 6)
          Text(statusLabel)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      // Toggle text input
      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          showTextInput.toggle()
        }
      } label: {
        Image(systemName: showTextInput ? "keyboard.chevron.compact.down" : "keyboard")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.primary)
      }
      .frame(width: 44, height: 44)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial)
  }

  // MARK: - Orb Visualizer

  private var orbSection: some View {
    VStack(spacing: 12) {
      AudioVisualizerView(
        inputLevel: viewModel.recorder.audioLevel,
        outputLevel: viewModel.player.outputLevel,
        isRecording: viewModel.isRecording,
        isSpeaking: viewModel.isSpeaking
      )
      .frame(width: 180, height: 180)
      .padding(.top, 20)

      // State label
      stateLabel
        .padding(.bottom, 12)
    }
  }

  private var stateLabel: some View {
    Group {
      if viewModel.isSpeaking {
        Label("Gemini is speaking", systemImage: "speaker.wave.2.fill")
          .foregroundStyle(Color(hex: "9B72CB"))
      } else if viewModel.isRecording {
        Label("Listening…", systemImage: "ear.fill")
          .foregroundStyle(Color(hex: "4285F4"))
      } else if viewModel.isMuted && viewModel.sessionStatus == .connected {
        Label("Muted", systemImage: "mic.slash")
          .foregroundStyle(.orange)
      } else if viewModel.sessionStatus == .connecting {
        Label("Connecting…", systemImage: "antenna.radiowaves.left.and.right")
          .foregroundStyle(.secondary)
      } else if viewModel.sessionStatus == .reconnecting {
        Label("Reconnecting…", systemImage: "arrow.triangle.2.circlepath")
          .foregroundStyle(.orange)
      } else {
        Label("Tap to connect", systemImage: "waveform")
          .foregroundStyle(.secondary)
      }
    }
    .font(.system(size: 13, weight: .medium))
    .animation(.easeInOut(duration: 0.3), value: viewModel.isSpeaking)
    .animation(.easeInOut(duration: 0.3), value: viewModel.isRecording)
  }

  // MARK: - Transcript

  private var transcriptArea: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 8) {
          if viewModel.transcript.isEmpty {
            emptyState
          }

          ForEach(viewModel.transcript) { entry in
            transcriptBubble(entry)
              .id(entry.id)
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
      }
      .onChange(of: viewModel.transcript.count) { _, _ in
        if let last = viewModel.transcript.last {
          withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
          }
        }
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Spacer().frame(height: 16)
      Image(systemName: "waveform.circle.fill")
        .font(.system(size: 40))
        .foregroundStyle(
          LinearGradient(
            colors: [Color(hex: "4285F4"), Color(hex: "9B72CB")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      Text("Start talking — Gemini is listening")
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Spacer()
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 32)
  }

  @ViewBuilder
  private func transcriptBubble(_ entry: LiveTranscriptEntry) -> some View {
    switch entry.role {
    case .user:
      HStack {
        Spacer()
        Text(entry.text)
          .font(.system(size: 14))
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(Color(hex: "4285F4"))
          .foregroundStyle(.white)
          .clipShape(RoundedRectangle(cornerRadius: 16))
      }

    case .assistant:
      HStack {
        Text(entry.text)
          .font(.system(size: 14))
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(Color(.systemGray5))
          .foregroundStyle(.primary)
          .clipShape(RoundedRectangle(cornerRadius: 16))
        Spacer()
      }

    case .system:
      HStack {
        Spacer()
        Text(entry.text)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .italic()
        Spacer()
      }

    case .error:
      HStack {
        Spacer()
        HStack(spacing: 4) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
          Text(entry.text)
            .font(.system(size: 12))
        }
        .foregroundStyle(.red)
        Spacer()
      }
    }
  }

  // MARK: - Text Input Bar

  private var textInputBar: some View {
    HStack(spacing: 10) {
      TextField("Type a message…", text: $textInput)
        .font(.system(size: 15))
        .textFieldStyle(.plain)
        .focused($isTextFieldFocused)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 20)
            .fill(Color(.secondarySystemBackground))
        )
        .disabled(viewModel.sessionStatus != .connected)
        .onSubmit { sendText() }

      if !textInput.isEmpty {
        Button {
          sendText()
        } label: {
          Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 28))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color(hex: "4285F4"))
        }
        .disabled(viewModel.sessionStatus != .connected)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }

  // MARK: - Controls Bar

  private var controlsBar: some View {
    HStack(spacing: 20) {
      Spacer()

      // Mic mute/unmute button
      Button {
        Task { await viewModel.toggleMute() }
      } label: {
        Image(systemName: viewModel.isRecording ? "mic.fill" : "mic.slash.fill")
          .font(.system(size: 20))
          .foregroundStyle(viewModel.isRecording ? .white : .orange)
          .frame(width: 52, height: 52)
          .background(
            viewModel.isRecording
              ? LinearGradient(
                  colors: [Color(hex: "4285F4"), Color(hex: "6C63FF")],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
              : LinearGradient(
                  colors: [Color(.systemGray5), Color(.systemGray5)],
                  startPoint: .top,
                  endPoint: .bottom
                )
          )
          .clipShape(Circle())
          .shadow(
            color: viewModel.isRecording ? Color(hex: "4285F4").opacity(0.3) : .clear,
            radius: 8, y: 2)
      }
      .disabled(viewModel.sessionStatus != .connected)
      .opacity(viewModel.sessionStatus != .connected ? 0.4 : 1)

      // Connect / Disconnect button
      Button {
        if viewModel.sessionStatus == .connected || viewModel.sessionStatus == .connecting {
          viewModel.disconnect()
        } else {
          viewModel.connect()
        }
      } label: {
        let isConnected =
          viewModel.sessionStatus == .connected
          || viewModel.sessionStatus == .connecting
        Image(systemName: isConnected ? "phone.down.fill" : "phone.fill")
          .font(.system(size: 20))
          .foregroundStyle(.white)
          .frame(width: 52, height: 52)
          .background(isConnected ? Color.red : Color.green)
          .clipShape(Circle())
          .shadow(
            color: isConnected ? Color.red.opacity(0.3) : Color.green.opacity(0.3),
            radius: 8, y: 2)
      }

      Spacer()
    }
    .padding(.vertical, 14)
    .background(.ultraThinMaterial)
  }

  // MARK: - Helpers

  private var statusDotColor: Color {
    switch viewModel.sessionStatus {
    case .idle: .gray
    case .connecting: .yellow
    case .connected: .green
    case .reconnecting: .orange
    case .error: .red
    }
  }

  private var statusLabel: String {
    switch viewModel.sessionStatus {
    case .idle: "Disconnected"
    case .connecting: "Connecting…"
    case .connected: "Connected"
    case .reconnecting: "Reconnecting…"
    case .error: "Error"
    }
  }

  private func sendText() {
    let trimmed = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    viewModel.sendText(trimmed)
    textInput = ""
    isTextFieldFocused = false
  }
}
