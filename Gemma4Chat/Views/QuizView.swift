import SwiftUI

struct QuizView: View {
  @Bindable var quizViewModel: QuizViewModel
  let modelName: String
  let onBack: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      // Header
      quizHeader

      // Main Body
      Group {
        if quizViewModel.isFinished {
          scoreCelebrationView
        } else if !quizViewModel.questions.isEmpty {
          activeQuizView
        } else {
          switch quizViewModel.status {
          case .idle:
            emptyState
          case .generating(let progressText):
            loadingView(progressText)
          case .failed(let message):
            failureView(message)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(
      LinearGradient(
        colors: [
          Color(.systemBackground),
          Color(hex: "4285F4").opacity(0.02),
          Color(hex: "9B72CB").opacity(0.02)
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    )
    .navigationBarHidden(true)
  }

  // MARK: - Header
  private var quizHeader: some View {
    HStack {
      Button(action: {
        quizViewModel.stopGeneration()
        onBack()
      }) {
        Image(systemName: "xmark")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.primary)
      }
      .frame(width: 44, height: 44)

      Spacer()

      VStack(spacing: 2) {
        Text("Gemma 4 Quiz")
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(.primary)

        Text(modelName)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
      }

      Spacer()

      // Empty spacer to balance header
      Spacer().frame(width: 44)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial)
  }

  // MARK: - Empty State
  private var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: "brain.head.profile")
        .font(.system(size: 48))
        .foregroundStyle(Color(hex: "9B72CB"))

      Text("Generate a Quiz")
        .font(.system(size: 20, weight: .semibold))

      Text("Please paste some content using the creation button.")
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - Loading View
  private func loadingView(_ text: String) -> some View {
    VStack(spacing: 24) {
      ProgressView()
        .controlSize(.large)
        .tint(Color(hex: "4285F4"))

      VStack(spacing: 8) {
        Text("Gemma 4 is drafting your quiz…")
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(.primary)

        Text(text)
          .font(.system(size: 13, weight: .medium, design: .monospaced))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 32)
      }

      Button(action: {
        quizViewModel.stopGeneration()
      }) {
        Text("Cancel Generation")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.red)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(
            Capsule().fill(Color.red.opacity(0.08))
          )
      }
    }
  }

  // MARK: - Failure View
  private func failureView(_ message: String) -> some View {
    VStack(spacing: 20) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 48))
        .foregroundStyle(.red)

      Text("Quiz Compilation Failed")
        .font(.system(size: 20, weight: .bold))

      Text(message)
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)

      Button(action: onBack) {
        Text("Go Back")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 24)
          .padding(.vertical, 12)
          .background(Color(hex: "4285F4"))
          .clipShape(RoundedRectangle(cornerRadius: 12))
      }
    }
  }

  // MARK: - Active Quiz View
  private var activeQuizView: some View {
    guard let question = quizViewModel.currentQuestion else { return AnyView(EmptyView()) }

    let currentNum = quizViewModel.currentQuestionIndex + 1
    let totalNum = quizViewModel.totalQuestionsCount
    let hasMoreToGenerate = quizViewModel.isStillGenerating

    return AnyView(
      ScrollView {
        VStack(spacing: 20) {
          // Progress Bar
          VStack(spacing: 6) {
            HStack {
              Text("Question \(currentNum) of \(totalNum)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
              
              if hasMoreToGenerate {
                Text("• Drafting more...")
                  .font(.system(size: 11, weight: .semibold))
                  .foregroundStyle(Color(hex: "9B72CB"))
                  .pulseEffect()
              }
              
              Spacer()
              
              Text("Score: \(quizViewModel.score)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: "4285F4"))
            }
            .padding(.horizontal, 4)

            let progress = Double(quizViewModel.currentQuestionIndex) / Double(max(1, Double(totalNum)))
            ProgressView(value: progress)
              .tint(Color(hex: "4285F4"))
          }
          .padding(.horizontal, 20)
          .padding(.top, 16)

          // Question Card
          VStack(alignment: .leading, spacing: 16) {
            Text(question.question)
              .font(.system(size: 18, weight: .bold))
              .foregroundStyle(.primary)
              .lineSpacing(4)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(20)
          .background(
            RoundedRectangle(cornerRadius: 20)
              .fill(Color(.secondarySystemBackground))
          )
          .padding(.horizontal, 20)

          // Options List
          VStack(spacing: 12) {
            ForEach(0..<question.options.count, id: \.self) { index in
              optionButton(option: question.options[index], index: index, question: question)
            }
          }
          .padding(.horizontal, 20)

          // Explanation Panel
          if quizViewModel.showExplanation {
            VStack(alignment: .leading, spacing: 8) {
              HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                  .foregroundStyle(Color(hex: "9B72CB"))
                Text("Explanation")
                  .font(.system(size: 14, weight: .bold))
                  .foregroundStyle(Color(hex: "9B72CB"))
              }

              Text(question.explanation)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "9B72CB").opacity(0.08))
                .overlay(
                  RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "9B72CB").opacity(0.15), lineWidth: 1)
                )
            )
            .padding(.horizontal, 20)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
          }

          // Next Button
          if quizViewModel.showExplanation {
            let isLastCurrentlyGenerated = currentNum == totalNum
            
            if isLastCurrentlyGenerated && hasMoreToGenerate {
              // Pulse loader while waiting for the next background question to compile!
              HStack(spacing: 8) {
                ProgressView()
                  .controlSize(.small)
                  .tint(Color(hex: "9B72CB"))
                Text("Gemma is writing question \(currentNum + 1) in real-time...")
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundStyle(Color(hex: "9B72CB"))
              }
              .frame(maxWidth: .infinity)
              .padding(.vertical, 14)
              .background(
                RoundedRectangle(cornerRadius: 14)
                  .fill(Color(hex: "9B72CB").opacity(0.05))
                  .overlay(
                    RoundedRectangle(cornerRadius: 14)
                      .stroke(Color(hex: "9B72CB").opacity(0.2), lineWidth: 1.5)
                  )
              )
              .padding(.horizontal, 20)
              .padding(.bottom, 24)
              .pulseEffect()
            } else {
              Button(action: {
                withAnimation {
                  quizViewModel.nextQuestion()
                }
              }) {
                HStack {
                  Text((isLastCurrentlyGenerated && !hasMoreToGenerate) ? "Finish Quiz" : "Next Question")
                    .font(.system(size: 16, weight: .semibold))
                  Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                }
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
                .shadow(color: Color(hex: "4285F4").opacity(0.2), radius: 10, y: 4)
              }
              .padding(.horizontal, 20)
              .padding(.bottom, 24)
              .transition(.scale.combined(with: .opacity))
            }
          }
        }
      }
    )
  }

  // MARK: - Option Button
  private func optionButton(option: String, index: Int, question: QuizQuestion) -> some View {
    let isSelected = quizViewModel.selectedOptionIndex == index
    let isAnswered = quizViewModel.selectedOptionIndex != nil
    let isCorrectAnswer = question.correctIndex == index

    var strokeColor: Color = Color.clear
    var bgColor: Color = Color(.secondarySystemBackground)
    var textColor: Color = .primary
    var checkIcon: String? = nil

    if isAnswered {
      if isCorrectAnswer {
        bgColor = Color.green.opacity(0.1)
        strokeColor = Color.green.opacity(0.4)
        textColor = .green
        checkIcon = "checkmark.circle.fill"
      } else if isSelected {
        bgColor = Color.red.opacity(0.1)
        strokeColor = Color.red.opacity(0.4)
        textColor = .red
        checkIcon = "xmark.circle.fill"
      }
    }

    return Button(action: {
      // Trigger simple impact haptic when selecting an option
      let generator = UIImpactFeedbackGenerator(style: .medium)
      generator.impactOccurred()
      
      withAnimation(.easeOut(duration: 0.25)) {
        quizViewModel.selectOption(index: index)
      }
    }) {
      HStack {
        Text(option)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(textColor)
          .multilineTextAlignment(.leading)
          .lineLimit(2)

        Spacer()

        if let iconName = checkIcon {
          Image(systemName: iconName)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(textColor)
        }
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 14)
      .background(
        RoundedRectangle(cornerRadius: 14)
          .fill(bgColor)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 14)
          .stroke(strokeColor, lineWidth: 1.5)
      )
    }
    .disabled(isAnswered)
  }

  // MARK: - Score Celebration View
  private var scoreCelebrationView: some View {
    VStack(spacing: 24) {
      Spacer().frame(height: 40)

      // Celebration Trophy
      ZStack {
        Circle()
          .fill(
            LinearGradient(
              colors: [Color(hex: "4285F4").opacity(0.15), Color(hex: "9B72CB").opacity(0.15)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: 140, height: 140)

        Image(systemName: "trophy.fill")
          .font(.system(size: 56))
          .foregroundStyle(
            LinearGradient(
              colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
              startPoint: .top,
              endPoint: .bottom
            )
          )
      }
      .shadow(color: Color(hex: "FFA500").opacity(0.25), radius: 20, y: 8)

      // Score Text
      VStack(spacing: 8) {
        Text("Quiz Completed!")
          .font(.system(size: 28, weight: .bold))
          .foregroundStyle(.primary)

        let questionsCount = quizViewModel.totalQuestionsCount
        Text("You scored **\(quizViewModel.score)** out of **\(questionsCount)** questions.")
          .font(.system(size: 16))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 32)
      }

      // Score Level Label
      let percentage = Double(quizViewModel.score) / Double(quizViewModel.totalQuestionsCount)
      let scoreLabel: String = {
        if percentage >= 0.9 { return "Excellent! 🌟" }
        if percentage >= 0.7 { return "Great Job! 👍" }
        if percentage >= 0.5 { return "Good Effort! 📚" }
        return "Keep Practicing! 📝"
      }()

      Text(scoreLabel)
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(Color(hex: "9B72CB"))
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
          Capsule().fill(Color(hex: "9B72CB").opacity(0.08))
        )

      Spacer()

      // Action Buttons
      VStack(spacing: 12) {
        Button(action: {
          quizViewModel.reset()
          onBack()
        }) {
          Text("Finish & Return")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
              LinearGradient(
                colors: [Color(hex: "4285F4"), Color(hex: "9B72CB")],
                startPoint: .leading,
                endPoint: .trailing
              )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
      }
      .padding(.horizontal, 32)
      .padding(.bottom, 32)
    }
  }
}
