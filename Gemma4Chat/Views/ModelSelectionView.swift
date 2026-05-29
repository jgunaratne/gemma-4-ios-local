import SwiftUI

/// Represents a selectable model option (local or cloud).
enum ModelOption: Hashable, Identifiable {
  case local(GemmaModel)
  case geminiCloud
  case geminiLive

  var id: String {
    switch self {
    case .local(let model): return model.id
    case .geminiCloud: return "gemini-cloud"
    case .geminiLive: return "gemini-live"
    }
  }

  var displayName: String {
    switch self {
    case .local(let model): return model.displayName
    case .geminiCloud: return "Gemini 3.5 Flash"
    case .geminiLive: return "Gemini Live 3.1"
    }
  }

  var subtitle: String {
    switch self {
    case .local(let model): return model.sizeDescription
    case .geminiCloud: return "Cloud API"
    case .geminiLive: return "Voice Chat"
    }
  }

  var info: String {
    switch self {
    case .local(let model): return model.info
    case .geminiCloud: return "Google's fastest cloud model with thinking capabilities. Requires an API key."
    case .geminiLive: return "Real-time voice conversation with Gemini. Speak and hear Gemini respond naturally."
    }
  }

  var isCloud: Bool {
    switch self {
    case .geminiCloud, .geminiLive: return true
    default: return false
    }
  }

  var isLive: Bool {
    if case .geminiLive = self { return true }
    return false
  }
}

struct ModelSelectionView: View {
  @Bindable var downloader: ModelDownloader
  let isInitializing: Bool
  let onStartChat: (ModelOption, String, String) -> Void
  let onCreateQuiz: (ModelOption) -> Void

  @AppStorage("geminiAPIKey") private var geminiAPIKey: String = ""
  @State private var editingAPIKey: String = ""
  @State private var isAPIKeyVisible: Bool = false
  @State private var selectedOption: ModelOption = .local(.gemma4_e4b)
  @AppStorage("contextText") private var contextText: String = ""
  @AppStorage("characterText") private var characterText: String = ""
  @State private var isGeneratingCharacter = false

  /// All model options: on-device models + Gemini cloud.
  private var allOptions: [ModelOption] {
    GemmaModel.allModels.map { .local($0) } + [.geminiCloud, .geminiLive]
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        // Header
        headerSection

        // Model selector
        modelSelector

        // API key section (shown for cloud models)
        if selectedOption.isCloud || selectedOption.isLive {
          apiKeySection
        }

        // Action buttons
        actionButtons

        Spacer().frame(height: 32)
      }
      .padding(.horizontal, 20)
    }
    .background(
      LinearGradient(
        colors: [
          Color(.systemBackground),
          Color(hex: "4285F4").opacity(0.03),
          Color(hex: "9B72CB").opacity(0.03),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    )
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      editingAPIKey = geminiAPIKey
    }
  }

  // MARK: - Header

  private var headerSection: some View {
    VStack(spacing: 12) {
      Spacer().frame(height: 20)

      // App icon
      ZStack {
        Circle()
          .fill(
            LinearGradient(
              colors: [Color(hex: "4285F4"), Color(hex: "9B72CB"), Color(hex: "D96570")],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: 80, height: 80)

        Image(systemName: "sparkles")
          .font(.system(size: 36, weight: .bold))
          .foregroundStyle(.white)
      }
      .shadow(color: Color(hex: "4285F4").opacity(0.3), radius: 20, y: 8)

      Text("Gemma 4 Chat")
        .font(.system(size: 32, weight: .bold))
        .foregroundStyle(
          LinearGradient(
            colors: [Color(hex: "4285F4"), Color(hex: "9B72CB")],
            startPoint: .leading,
            endPoint: .trailing
          )
        )

      Text("On-device & cloud AI conversations")
        .font(.system(size: 16))
        .foregroundStyle(.secondary)

      if isInitializing {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Loading model…")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
      }
    }
    .padding(.bottom, 8)
  }

  // MARK: - Model Selector

  private var modelSelector: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Select Model")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.leading, 4)

      VStack(spacing: 0) {
        ForEach(Array(allOptions.enumerated()), id: \.element.id) { index, option in
          modelRow(option)

          if index < allOptions.count - 1 {
            Divider()
              .padding(.leading, 52)
          }
        }
      }
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(Color(.secondarySystemBackground))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 16)
          .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
      )
    }
  }

  private func modelRow(_ option: ModelOption) -> some View {
    let isSelected = selectedOption == option
    let downloadStatus = localDownloadStatus(for: option)

    return Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        selectedOption = option
      }
    } label: {
      HStack(spacing: 14) {
        // Radio button
        ZStack {
          Circle()
            .stroke(
              isSelected ? Color(hex: "4285F4") : Color(.systemGray3),
              lineWidth: 2
            )
            .frame(width: 22, height: 22)

          if isSelected {
            Circle()
              .fill(Color(hex: "4285F4"))
              .frame(width: 12, height: 12)
          }
        }

        // Model info
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Text(option.displayName)
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(.primary)

            if option.isLive {
              Text("Voice")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                  Capsule()
                    .fill(
                      LinearGradient(
                        colors: [Color(hex: "9B72CB"), Color(hex: "D96570")],
                        startPoint: .leading,
                        endPoint: .trailing
                      )
                    )
                )
            } else if option.isCloud {
              Text("Cloud")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                  Capsule()
                    .fill(
                      LinearGradient(
                        colors: [Color(hex: "4285F4"), Color(hex: "34A853")],
                        startPoint: .leading,
                        endPoint: .trailing
                      )
                    )
                )
            }
          }

          Text(option.subtitle)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }

        Spacer()

        // Status badge
        statusBadge(for: option, downloadStatus: downloadStatus)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func statusBadge(for option: ModelOption, downloadStatus: DownloadStatus?) -> some View {
    if option.isLive {
      HStack(spacing: 4) {
        Image(systemName: "waveform")
          .font(.system(size: 10))
        Text("Ready")
          .font(.system(size: 11, weight: .semibold))
      }
      .foregroundStyle(Color(hex: "9B72CB"))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Capsule().fill(Color(hex: "9B72CB").opacity(0.12)))
    } else if option.isCloud {
      HStack(spacing: 4) {
        Image(systemName: "bolt.fill")
          .font(.system(size: 10))
        Text("Ready")
          .font(.system(size: 11, weight: .semibold))
      }
      .foregroundStyle(Color.green)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Capsule().fill(Color.green.opacity(0.12)))
    } else if let status = downloadStatus {
      switch status {
      case .downloaded:
        HStack(spacing: 4) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 10))
          Text("Ready")
            .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color.green)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.green.opacity(0.12)))

      case .downloading(let progress):
        HStack(spacing: 4) {
          ProgressView()
            .controlSize(.mini)
          Text("\(Int(progress * 100))%")
            .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color(hex: "4285F4"))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color(hex: "4285F4").opacity(0.12)))

      case .notDownloaded:
        Text("Not Downloaded")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(Capsule().fill(Color(.systemGray5)))

      case .failed:
        HStack(spacing: 4) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
          Text("Failed")
            .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.red.opacity(0.12)))
      }
    }
  }

  // MARK: - API Key Section

  private var apiKeySection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Gemini API Key")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.leading, 4)

      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          Group {
            if isAPIKeyVisible {
              TextField("Paste your API key", text: $editingAPIKey)
            } else {
              SecureField("Paste your API key", text: $editingAPIKey)
            }
          }
          .textFieldStyle(.plain)
          .font(.system(size: 14, design: .monospaced))
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
          .padding(.horizontal, 14)
          .padding(.vertical, 12)

          Button {
            isAPIKeyVisible.toggle()
          } label: {
            Image(systemName: isAPIKeyVisible ? "eye.slash.fill" : "eye.fill")
              .font(.system(size: 14))
              .foregroundStyle(.secondary)
              .frame(width: 36, height: 36)
          }
          .padding(.trailing, 8)
        }
        .background(
          RoundedRectangle(cornerRadius: 12)
            .fill(Color(.tertiarySystemBackground))
        )
        .onChange(of: editingAPIKey) { _, newValue in
          geminiAPIKey = newValue
        }

        Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
          HStack(spacing: 4) {
            Image(systemName: "arrow.up.right.square")
              .font(.system(size: 11))
            Text("Get an API key from Google AI Studio")
              .font(.system(size: 12, weight: .medium))
          }
          .foregroundStyle(Color(hex: "4285F4"))
        }
        .padding(.leading, 4)
      }
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(Color(.secondarySystemBackground))
    )
  }

  // MARK: - Action Buttons

  private var actionButtons: some View {
    VStack(spacing: 12) {
      // Download button (only for local models that aren't downloaded)
      if case .local(let model) = selectedOption {
        let status = downloader.status(for: model)

        if case .downloading(let progress) = status {
          VStack(spacing: 8) {
            ProgressView(value: progress)
              .tint(Color(hex: "4285F4"))

            HStack {
              Text("Downloading… \(Int(progress * 100))%")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
              Spacer()
              Button("Cancel") {
                downloader.cancelDownload(model)
              }
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(.red)
            }
          }
          .padding(16)
          .background(
            RoundedRectangle(cornerRadius: 16)
              .fill(Color(.secondarySystemBackground))
          )
        }

        if !status.isDownloaded && !status.isDownloading {
          Button {
            downloader.downloadModel(model)
          } label: {
            HStack {
              Image(systemName: "arrow.down.circle.fill")
              Text("Download \(model.displayName)")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
              LinearGradient(
                colors: [Color(hex: "4285F4"), Color(hex: "6C63FF")],
                startPoint: .leading,
                endPoint: .trailing
              )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
          }
        }
      }

      // Start Chat button
      Button {
        if selectedOption.isCloud, editingAPIKey != geminiAPIKey {
          geminiAPIKey = editingAPIKey
        }
        onStartChat(selectedOption, contextText, characterText)
      } label: {
        HStack {
          Image(systemName: selectedOption.isLive ? "waveform" : "message.fill")
          Text(selectedOption.isLive ? "Start Voice Chat" : "Start Chat")
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
          LinearGradient(
            colors: canStartChat
              ? (selectedOption.isLive
                ? [Color(hex: "9B72CB"), Color(hex: "D96570")]
                : [Color(hex: "4285F4"), Color(hex: "6C63FF")])
              : [Color(.systemGray3), Color(.systemGray3)],
            startPoint: .leading,
            endPoint: .trailing
          )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(
          color: canStartChat
            ? (selectedOption.isLive ? Color(hex: "9B72CB").opacity(0.2) : Color(hex: "4285F4").opacity(0.2))
            : .clear,
          radius: 10, y: 4)
      }
      .disabled(!canStartChat || isInitializing)
      .opacity((!canStartChat || isInitializing) ? 0.6 : 1)

      // Create Quiz button
      Button {
        if selectedOption.isCloud, editingAPIKey != geminiAPIKey {
          geminiAPIKey = editingAPIKey
        }
        onCreateQuiz(selectedOption)
      } label: {
        HStack {
          Image(systemName: "brain.head.profile")
          Text("Create Quiz")
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Color(hex: "9B72CB"))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
          RoundedRectangle(cornerRadius: 14)
            .stroke(Color(hex: "9B72CB").opacity(0.4), lineWidth: 1.5)
            .background(Color(hex: "9B72CB").opacity(0.05))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
      }
      .disabled(!canStartChat || isInitializing)
      .opacity((!canStartChat || isInitializing) ? 0.6 : 1)

      // Context input
      contextSection

      // Character narrator
      characterSection

      // Delete button (only for downloaded local models)
      if case .local(let model) = selectedOption, downloader.status(for: model).isDownloaded {
        Button {
          downloader.deleteModel(model)
        } label: {
          HStack {
            Image(systemName: "trash")
            Text("Delete Model")
          }
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(.red)
        }
        .padding(.top, 4)
      }
    }
  }

  // MARK: - Context Section

  private var contextSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(systemName: "doc.text.fill")
          .font(.system(size: 14))
          .foregroundStyle(Color(hex: "4285F4"))
        Text("Context")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.primary)
        Spacer()
        if !contextText.isEmpty {
          Button {
            contextText = ""
          } label: {
            Text("Clear")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(.red)
          }
        }
      }

      Text("Paste text (e.g. a podcast transcript, article, or notes) to use as context for your conversation.")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)

      TextEditor(text: $contextText)
        .font(.system(size: 14))
        .scrollContentBackground(.hidden)
        .frame(minHeight: 80, maxHeight: 160)
        .padding(10)
        .background(
          RoundedRectangle(cornerRadius: 12)
            .fill(Color(.secondarySystemBackground))
        )
        .overlay(
          Group {
            if contextText.isEmpty {
              Text("Paste your context here…")
                .font(.system(size: 14))
                .foregroundStyle(.quaternary)
                .padding(.leading, 14)
                .padding(.top, 18)
            }
          },
          alignment: .topLeading
        )

      if !contextText.isEmpty {
        HStack(spacing: 4) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 11))
            .foregroundStyle(.green)
          Text("\(contextText.count.formatted()) characters")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(Color(.secondarySystemBackground))
    )
  }

  // MARK: - Character Section

  private var characterSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(systemName: "person.text.rectangle.fill")
          .font(.system(size: 14))
          .foregroundStyle(Color(hex: "9B72CB"))
        Text("Character Narrator")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.primary)
        Spacer()
        if !characterText.isEmpty {
          Button {
            characterText = ""
          } label: {
            Text("Clear")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(.red)
          }
        }
      }

      Text("Specify a persona/character who should be reading your context and what they should sound like (e.g., a crisp British reporter, a mysterious ancient wizard, a cheerful tech podcaster).")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)

      TextEditor(text: $characterText)
        .font(.system(size: 14))
        .scrollContentBackground(.hidden)
        .frame(minHeight: 80, maxHeight: 120)
        .padding(10)
        .background(
          RoundedRectangle(cornerRadius: 12)
            .fill(Color(.secondarySystemBackground))
        )
        .overlay(
          Group {
            if characterText.isEmpty {
              Text("Describe the character or tap 'Generate' below…")
                .font(.system(size: 14))
                .foregroundStyle(.quaternary)
                .padding(.leading, 14)
                .padding(.top, 18)
            }
          },
          alignment: .topLeading
        )

      // Generate Button
      Button {
        generateCharacterNarrator()
      } label: {
        HStack {
          if isGeneratingCharacter {
            ProgressView()
              .tint(.white)
              .padding(.trailing, 4)
            Text("Generating Persona…")
          } else {
            Image(systemName: "sparkles")
            Text("Generate Character Narrator")
          }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
          LinearGradient(
            colors: canGenerateCharacter
              ? [Color(hex: "9B72CB"), Color(hex: "D96570")]
              : [Color(.systemGray4), Color(.systemGray4)],
            startPoint: .leading,
            endPoint: .trailing
          )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
      }
      .disabled(!canGenerateCharacter || isGeneratingCharacter)
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(Color(.secondarySystemBackground))
    )
  }

  private var canGenerateCharacter: Bool {
    !contextText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
    !editingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func generateCharacterNarrator() {
    let key = editingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let context = contextText.trimmingCharacters(in: .whitespacesAndNewlines)
    
    guard !key.isEmpty, !context.isEmpty else { return }
    
    isGeneratingCharacter = true
    
    let prompt = """
    You are a world-class director, creative writer, and casting agent.
    Your job is to analyze the provided content/transcript and design a highly compelling, specific voice character/narrator who is perfect for reading, presenting, or having a live conversation about this text.

    Task:
    1. Analyze the speakers in the text below. Identify their accent, speech style, speed, specific vocabulary/language choices, and their overall personality traits.
    2. Design a character persona who mirrors this exact same style of accent, speech, language, and personality of the speakers in the podcast/context.
    3. Write a detailed, concise 1-2 paragraph character description. Include details like their profession, age, gender/accent, emotional tone, speech pacing, vocabulary style (e.g., uses formal wording, uses friendly contractions, uses specific jargon), and specific guidelines for how they should speak (e.g., "Keep responses short, conversational, match their regional accent, and use the same informal vocabulary").

    Content:
    \"\"\"
    \(context)
    \"\"\"

    Output only the resulting 1-2 paragraph character description. Do not include headers, bullet points, or introductory text. Keep it extremely focused on the persona and speech style guidelines.
    """
    
    Task {
      do {
        let response = try await GeminiAPIService.generateContent(apiKey: key, prompt: prompt)
        await MainActor.run {
          self.characterText = response.trimmingCharacters(in: .whitespacesAndNewlines)
          self.isGeneratingCharacter = false
        }
      } catch {
        print("❌ [ModelSelection] Failed to generate character narrator: \(error.localizedDescription)")
        await MainActor.run {
          self.isGeneratingCharacter = false
        }
      }
    }
  }

  // MARK: - Helpers

  /// Whether the current selection is ready for chat/quiz.
  private var canStartChat: Bool {
    switch selectedOption {
    case .local(let model):
      return downloader.status(for: model).isDownloaded
    case .geminiCloud:
      return !editingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .geminiLive:
      return !editingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  private func localDownloadStatus(for option: ModelOption) -> DownloadStatus? {
    if case .local(let model) = option {
      return downloader.status(for: model)
    }
    return nil
  }
}
