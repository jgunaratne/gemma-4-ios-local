import SwiftUI

/// Chat view for the Gemini cloud API.
/// Mirrors the existing ChatView UI but uses GeminiChatViewModel instead of the local inference service.
struct GeminiChatView: View {
  @Bindable var chatViewModel: GeminiChatViewModel
  let modelName: String
  let onNewChat: () -> Void
  let onBack: () -> Void

  @State private var inputText = ""
  @FocusState private var isInputFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      // Header
      chatHeader

      // Messages
      messagesArea

      // Input bar
      inputBar
    }
    .background(Color(.systemBackground))
    .navigationBarHidden(true)
  }

  // MARK: - Header
  private var chatHeader: some View {
    HStack {
      Button(action: onBack) {
        Image(systemName: "chevron.left")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.primary)
      }
      .frame(width: 44, height: 44)

      Spacer()

      VStack(spacing: 2) {
        Text(modelName)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.primary)

        HStack(spacing: 4) {
          Circle()
            .fill(statusColor)
            .frame(width: 6, height: 6)
          Text(statusText)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      Button(action: onNewChat) {
        Image(systemName: "square.and.pencil")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.primary)
      }
      .frame(width: 44, height: 44)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial)
  }

  private var statusColor: Color {
    chatViewModel.isGenerating ? .orange : .green
  }

  private var statusText: String {
    chatViewModel.isGenerating ? "Generating…" : "Ready"
  }

  // MARK: - Messages Area
  private var messagesArea: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 16) {
          if chatViewModel.messages.isEmpty {
            emptyState
          }

          ForEach(chatViewModel.messages) { message in
            MessageBubble(message: message)
              .id(message.id)
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
      }
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: chatViewModel.messages.count) { _, _ in
        scrollToBottom(proxy: proxy)
      }
      .onChange(of: chatViewModel.messages.last?.content) { _, _ in
        if chatViewModel.isGenerating {
          scrollToBottom(proxy: proxy, animated: false)
        }
      }
    }
  }

  private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
    if let lastId = chatViewModel.messages.last?.id {
      if animated {
        withAnimation(.easeOut(duration: 0.25)) {
          proxy.scrollTo(lastId, anchor: .bottom)
        }
      } else {
        proxy.scrollTo(lastId, anchor: .bottom)
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Spacer().frame(height: 60)

      Image(systemName: "bolt.fill")
        .font(.system(size: 48))
        .foregroundStyle(
          LinearGradient(
            colors: [Color(hex: "4285F4"), Color(hex: "34A853")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )

      Text("Gemini 3.5 Flash")
        .font(.system(size: 28, weight: .bold))
        .foregroundStyle(
          LinearGradient(
            colors: [Color(hex: "4285F4"), Color(hex: "34A853")],
            startPoint: .leading,
            endPoint: .trailing
          )
        )

      Text("Powered by Google's cloud API.\nFast, capable, and always up to date.")
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      // Suggested prompts
      VStack(spacing: 8) {
        promptChip("Summarize the latest AI trends")
        promptChip("Write a Python sorting algorithm")
        promptChip("Plan a weekend trip to Big Sur")
      }
      .padding(.top, 12)

      Spacer()
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 32)
  }

  private func promptChip(_ text: String) -> some View {
    Button {
      inputText = text
      sendMessage()
    } label: {
      HStack {
        Image(systemName: "sparkle")
          .font(.system(size: 12))
        Text(text)
          .font(.system(size: 14))
          .lineLimit(1)
      }
      .foregroundStyle(Color(hex: "4285F4"))
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(
        Capsule()
          .fill(Color(hex: "4285F4").opacity(0.08))
          .overlay(
            Capsule()
              .stroke(Color(hex: "4285F4").opacity(0.15), lineWidth: 1)
          )
      )
    }
    .disabled(chatViewModel.isGenerating)
  }

  // MARK: - Input Bar
  private var inputBar: some View {
    VStack(spacing: 0) {
      Divider()

      HStack(alignment: .bottom, spacing: 12) {
        // Text input
        HStack(alignment: .bottom) {
          TextField("Message…", text: $inputText, axis: .vertical)
            .lineLimit(1...6)
            .textFieldStyle(.plain)
            .font(.system(size: 16))
            .focused($isInputFocused)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .submitLabel(.send)
            .onSubmit {
              sendMessage()
            }
        }
        .background(
          RoundedRectangle(cornerRadius: 24)
            .fill(Color(.secondarySystemBackground))
        )

        // Send / Stop button
        Button {
          if chatViewModel.isGenerating {
            chatViewModel.stopGeneration()
          } else {
            sendMessage()
          }
        } label: {
          ZStack {
            Circle()
              .fill(
                canSend || chatViewModel.isGenerating
                  ? LinearGradient(
                    colors: [Color(hex: "4285F4"), Color(hex: "34A853")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                  )
                  : LinearGradient(
                    colors: [Color(.systemGray4), Color(.systemGray4)],
                    startPoint: .top,
                    endPoint: .bottom
                  )
              )
              .frame(width: 40, height: 40)

            Image(systemName: chatViewModel.isGenerating ? "stop.fill" : "arrow.up")
              .font(.system(size: chatViewModel.isGenerating ? 14 : 18, weight: .bold))
              .foregroundStyle(.white)
          }
        }
        .disabled(!canSend && !chatViewModel.isGenerating)
        .animation(.easeInOut(duration: 0.2), value: canSend)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(.ultraThinMaterial)
    }
  }

  private var canSend: Bool {
    !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !chatViewModel.isGenerating
  }

  private func sendMessage() {
    let text = inputText
    inputText = ""
    chatViewModel.sendMessage(text)
  }
}
