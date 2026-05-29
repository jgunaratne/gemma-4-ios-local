import SwiftUI

/// Card component for the Gemini 3.5 Flash cloud model on the model selection screen.
/// Shows an API key input field and a "Start Chat" button.
struct GeminiFlashCard: View {
  @Binding var savedAPIKey: String
  let isInitializing: Bool
  let onSelect: (String) -> Void

  @State private var editingAPIKey: String = ""
  @State private var isAPIKeyVisible: Bool = false
  @State private var showSavedConfirmation: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      // Title row
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            Text("Gemini 3.5 Flash")
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(.primary)

            Text("Cloud")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(.white)
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
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

          Text("Streaming • No download required")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
        }

        Spacer()

        // Cloud icon badge
        HStack(spacing: 4) {
          Image(systemName: "bolt.fill")
            .font(.system(size: 12))
          Text("Ready")
            .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(hasAPIKey ? Color.green : Color.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
          Capsule()
            .fill(hasAPIKey ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
        )
      }

      // Info
      Text("Google's fastest cloud model with thinking capabilities. Requires an API key from Google AI Studio.")
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
        .lineLimit(3)

      // API Key input section
      VStack(alignment: .leading, spacing: 8) {
        Text("Gemini API Key")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.secondary)

        HStack(spacing: 8) {
          Group {
            if isAPIKeyVisible {
              TextField("Paste your API key here", text: $editingAPIKey)
            } else {
              SecureField("Paste your API key here", text: $editingAPIKey)
            }
          }
          .textFieldStyle(.plain)
          .font(.system(size: 14, design: .monospaced))
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .background(
            RoundedRectangle(cornerRadius: 10)
              .fill(Color(.tertiarySystemBackground))
          )

          // Toggle visibility button
          Button {
            isAPIKeyVisible.toggle()
          } label: {
            Image(systemName: isAPIKeyVisible ? "eye.slash.fill" : "eye.fill")
              .font(.system(size: 14))
              .foregroundStyle(.secondary)
              .frame(width: 36, height: 36)
              .background(
                RoundedRectangle(cornerRadius: 10)
                  .fill(Color(.tertiarySystemBackground))
              )
          }
        }

        // Save confirmation
        if showSavedConfirmation {
          HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 11))
            Text("Key saved")
              .font(.system(size: 12, weight: .medium))
          }
          .foregroundStyle(.green)
          .transition(.opacity.combined(with: .move(edge: .top)))
        }

        // Get API key link
        Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
          HStack(spacing: 4) {
            Image(systemName: "arrow.up.right.square")
              .font(.system(size: 11))
            Text("Get an API key from Google AI Studio")
              .font(.system(size: 12, weight: .medium))
          }
          .foregroundStyle(Color(hex: "4285F4"))
        }
      }

      // Action button
      Button {
        // Save the key.
        if editingAPIKey != savedAPIKey {
          savedAPIKey = editingAPIKey
          withAnimation {
            showSavedConfirmation = true
          }
          DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
              showSavedConfirmation = false
            }
          }
        }
        onSelect(editingAPIKey)
      } label: {
        HStack {
          Image(systemName: "message.fill")
          Text("Start Chat")
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(
          LinearGradient(
            colors: hasAPIKey
              ? [Color(hex: "4285F4"), Color(hex: "34A853")]
              : [Color(.systemGray3), Color(.systemGray3)],
            startPoint: .leading,
            endPoint: .trailing
          )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
      }
      .disabled(!hasAPIKey || isInitializing)
      .opacity((!hasAPIKey || isInitializing) ? 0.6 : 1)
    }
    .padding(18)
    .background(
      RoundedRectangle(cornerRadius: 20)
        .fill(Color(.secondarySystemBackground))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 20)
        .stroke(
          hasAPIKey
            ? Color(hex: "34A853").opacity(0.3)
            : Color.clear,
          lineWidth: 1.5
        )
    )
    .onAppear {
      editingAPIKey = savedAPIKey
    }
  }

  private var hasAPIKey: Bool {
    !editingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
