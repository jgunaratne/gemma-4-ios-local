import SwiftUI

struct RootView: View {
  @State private var modelDownloader = ModelDownloader()
  @State private var inferenceService = LLMInferenceService()
  @State private var chatViewModel: ChatViewModel?
  @State private var quizViewModel: QuizViewModel?
  @State private var selectedModel: GemmaModel?
  
  @State private var showChat = false
  @State private var showQuiz = false
  @State private var showCreationSheet = false
  @State private var isInitializing = false
  @State private var pastedText = ""

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
      } else {
        ModelSelectionView(
          downloader: modelDownloader,
          isInitializing: isInitializing,
          onModelSelected: { model in
            selectModel(model)
          },
          onModelSelectedForQuiz: { model in
            selectedModel = model
            showCreationSheet = true
          }
        )
        .transition(.move(edge: .leading))
        .sheet(isPresented: $showCreationSheet) {
          QuizCreationSheet(
            text: $pastedText,
            onGenerate: {
              showCreationSheet = false
              if let model = selectedModel {
                startQuizFlow(model: model, text: pastedText)
              }
              pastedText = ""
            },
            onDismiss: {
              showCreationSheet = false
              selectedModel = nil
              pastedText = ""
            }
          )
        }
      }
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

  private func startQuizFlow(model: GemmaModel, text: String) {
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
}
