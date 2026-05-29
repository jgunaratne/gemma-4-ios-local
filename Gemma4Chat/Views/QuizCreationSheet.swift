import SwiftUI

struct QuizCreationSheet: View {
  @Binding var text: String
  let onGenerate: () -> Void
  let onDismiss: () -> Void

  @FocusState private var isFocused: Bool

  var body: some View {
    NavigationStack {
      VStack(spacing: 18) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Generate a Quiz")
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(
              LinearGradient(
                colors: [Color(hex: "4285F4"), Color(hex: "9B72CB")],
                startPoint: .leading,
                endPoint: .trailing
              )
            )

          Text("Paste any content (articles, transcripts, or notes) and Gemma 4 will compile a custom 10-question multiple-choice quiz for you.")
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)

        // Paste Area
        ZStack(alignment: .topLeading) {
          if text.isEmpty {
            Text("Paste your text here…")
              .font(.system(size: 15))
              .foregroundStyle(.placeholder)
              .padding(.horizontal, 16)
              .padding(.vertical, 14)
              .allowsHitTesting(false)
          }

          TextEditor(text: $text)
            .font(.system(size: 15))
            .focused($isFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 20)

        // Generate Button
        Button(action: {
          isFocused = false
          onGenerate()
        }) {
          HStack {
            Image(systemName: "brain.head.profile")
              .font(.system(size: 16, weight: .semibold))
            Text("Generate 10-Question Quiz")
              .font(.system(size: 16, weight: .semibold))
          }
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
          .shadow(color: Color(hex: "4285F4").opacity(0.2), radius: 10, y: 4)
        }
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
      }
      .background(Color(.systemBackground))
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel", action: onDismiss)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.secondary)
        }
      }
      .onAppear {
        isFocused = true
      }
    }
  }
}
