import SwiftUI

struct RootView: View {
  @State private var modelDownloader = ModelDownloader()
  @State private var inferenceService = LLMInferenceService()
  @State private var chatViewModel: ChatViewModel?
  @State private var quizViewModel: QuizViewModel?
  @State private var geminiChatViewModel: GeminiChatViewModel?
  @State private var geminiQuizViewModel: GeminiQuizViewModel?
  @State private var liveChatViewModel: LiveChatViewModel?
  @State private var selectedModel: GemmaModel?
  @State private var selectedModelOption: ModelOption?
  
  @State private var showChat = false
  @State private var showQuiz = false
  @State private var showGeminiChat = false
  @State private var showGeminiQuiz = false
  @State private var showLiveChat = false
  @State private var showCreationSheet = false
  @State private var isInitializing = false
  @State private var pastedText = ""

  @AppStorage("geminiAPIKey") private var geminiAPIKey: String = ""

  var body: some View {
    NavigationStack {
      if showChat, let model = selectedModel, let chatVM = chatViewModel {
        ChatView(
          chatViewModel: chatVM,
          inferenceService: inferenceService,
          modelName: model.displayName,
          onNewChat: {
            await chatVM.clearMessages()
          },
          onBack: {
            withAnimation {
              showChat = false
            }
            inferenceService.cleanup()
          }
        )
        .transition(.move(edge: .trailing))
      } else if showGeminiChat, let geminiVM = geminiChatViewModel {
        GeminiChatView(
          chatViewModel: geminiVM,
          modelName: "Gemini 3.5 Flash",
          onNewChat: {
            geminiVM.clearMessages()
          },
          onBack: {
            withAnimation {
              showGeminiChat = false
            }
          }
        )
        .transition(.move(edge: .trailing))
      } else if showQuiz, let model = selectedModel, let quizVM = quizViewModel {
        QuizView(
          quizViewModel: quizVM,
          modelName: model.displayName,
          onBack: {
            withAnimation {
              showQuiz = false
            }
            inferenceService.cleanup()
          }
        )
        .transition(.move(edge: .trailing))
      } else if showGeminiQuiz, let geminiQVM = geminiQuizViewModel {
        GeminiQuizView(
          quizViewModel: geminiQVM,
          modelName: "Gemini 3.5 Flash",
          onBack: {
            withAnimation {
              showGeminiQuiz = false
            }
          }
        )
        .transition(.move(edge: .trailing))
      } else if showLiveChat, let liveVM = liveChatViewModel {
        LiveChatView(
          viewModel: liveVM,
          onBack: {
            withAnimation {
              showLiveChat = false
            }
          }
        )
        .transition(.move(edge: .trailing))
      } else {
        ModelSelectionView(
          downloader: modelDownloader,
          isInitializing: isInitializing,
          onStartChat: { option in
            handleStartChat(option)
          },
          onCreateQuiz: { option in
            selectedModelOption = option
            showCreationSheet = true
          }
        )
        .transition(.move(edge: .leading))
        .sheet(isPresented: $showCreationSheet) {
          QuizCreationSheet(
            text: $pastedText,
            onGenerate: {
              showCreationSheet = false
              if let option = selectedModelOption {
                handleCreateQuiz(option, text: pastedText)
              }
              pastedText = ""
            },
            onDismiss: {
              showCreationSheet = false
              selectedModelOption = nil
              pastedText = ""
            }
          )
        }
      }
    }
  }

  // MARK: - Start Chat

  private func handleStartChat(_ option: ModelOption) {
    switch option {
    case .local(let model):
      selectModel(model)
    case .geminiCloud:
      selectGemini(apiKey: geminiAPIKey)
    case .geminiLive:
      selectGeminiLive(apiKey: geminiAPIKey)
    }
  }

  private func selectModel(_ model: GemmaModel) {
    selectedModel = model
    isInitializing = true

    let service = inferenceService
    let vm = ChatViewModel(inferenceService: service)
    chatViewModel = vm

    Task {
      await service.initializeEngine(model: model)
      isInitializing = false
      withAnimation {
        showChat = true
      }
    }
  }

  private func selectGemini(apiKey: String) {
    let vm = GeminiChatViewModel(apiKey: apiKey)
    geminiChatViewModel = vm
    withAnimation {
      showGeminiChat = true
    }
  }

  private func selectGeminiLive(apiKey: String) {
    let vm = LiveChatViewModel(apiKey: apiKey)
    liveChatViewModel = vm
    withAnimation {
      showLiveChat = true
    }
  }

  // MARK: - Create Quiz

  private func handleCreateQuiz(_ option: ModelOption, text: String) {
    switch option {
    case .local(let model):
      startLocalQuizFlow(model: model, text: text)
    case .geminiCloud:
      startGeminiQuizFlow(text: text)
    case .geminiLive:
      // Live voice mode doesn't support quiz — use Gemini Cloud as fallback
      startGeminiQuizFlow(text: text)
    }
  }

  private func startLocalQuizFlow(model: GemmaModel, text: String) {
    selectedModel = model
    isInitializing = true

    let service = inferenceService
    let vm = QuizViewModel(inferenceService: service)
    quizViewModel = vm

    Task {
      await service.initializeEngine(model: model, systemPrompt: "", temperature: 0.15, forceCPU: true)
      isInitializing = false
      withAnimation {
        showQuiz = true
      }
      vm.generateQuiz(from: text)
    }
  }

  private func startGeminiQuizFlow(text: String) {
    let vm = GeminiQuizViewModel(apiKey: geminiAPIKey)
    geminiQuizViewModel = vm
    withAnimation {
      showGeminiQuiz = true
    }
    vm.generateQuiz(from: text)
  }
}
