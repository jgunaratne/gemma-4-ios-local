import SwiftUI

struct ModelSelectionView: View {
  @Bindable var downloader: ModelDownloader
  let isInitializing: Bool
  let onModelSelected: (GemmaModel) -> Void
  let onModelSelectedForQuiz: (GemmaModel) -> Void

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        // Header
        headerSection

        // Model cards
        ForEach(GemmaModel.allModels) { model in
          ModelCard(
            model: model,
            status: downloader.status(for: model),
            isInitializing: isInitializing,
            onDownload: { downloader.downloadModel(model) },
            onCancel: { downloader.cancelDownload(model) },
            onDelete: { downloader.deleteModel(model) },
            onSelect: { onModelSelected(model) },
            onSelectQuiz: { onModelSelectedForQuiz(model) }
          )
        }

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
  }

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

      Text("Private, on-device AI conversations")
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
}

// MARK: - Model Card
struct ModelCard: View {
  let model: GemmaModel
  let status: DownloadStatus
  let isInitializing: Bool
  let onDownload: () -> Void
  let onCancel: () -> Void
  let onDelete: () -> Void
  let onSelect: () -> Void
  let onSelectQuiz: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      // Title row
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(model.displayName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)

          Text(model.sizeDescription)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
        }

        Spacer()

        statusBadge
      }

      // Info
      Text(model.info)
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
        .lineLimit(2)

      // Progress bar for downloading
      if case let .downloading(progress) = status {
        VStack(spacing: 6) {
          ProgressView(value: progress)
            .tint(Color(hex: "4285F4"))

          HStack {
            Text("\(Int(progress * 100))%")
              .font(.system(size: 12, weight: .medium, design: .monospaced))
              .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel", action: onCancel)
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(.red)
          }
        }
      }

      // Error message
      if case let .failed(message) = status {
        Text(message)
          .font(.system(size: 12))
          .foregroundStyle(.red)
          .lineLimit(2)
      }

      // Action button
      actionButton
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
          status.isDownloaded
            ? Color(hex: "4285F4").opacity(0.3)
            : Color.clear,
          lineWidth: 1.5
        )
    )
  }

  @ViewBuilder
  private var statusBadge: some View {
    switch status {
    case .downloaded:
      HStack(spacing: 4) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 12))
        Text("Ready")
          .font(.system(size: 12, weight: .semibold))
      }
      .foregroundStyle(Color.green)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(
        Capsule().fill(Color.green.opacity(0.12))
      )

    case .downloading:
      HStack(spacing: 4) {
        ProgressView()
          .controlSize(.mini)
        Text("Downloading")
          .font(.system(size: 12, weight: .semibold))
      }
      .foregroundStyle(Color(hex: "4285F4"))
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(
        Capsule().fill(Color(hex: "4285F4").opacity(0.12))
      )

    case .failed:
      HStack(spacing: 4) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 12))
        Text("Failed")
          .font(.system(size: 12, weight: .semibold))
      }
      .foregroundStyle(.red)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(
        Capsule().fill(Color.red.opacity(0.12))
      )

    case .notDownloaded:
      EmptyView()
    }
  }

  @ViewBuilder
  private var actionButton: some View {
    switch status {
    case .downloaded:
      VStack(spacing: 12) {
        HStack(spacing: 12) {
          Button(action: onSelect) {
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
                colors: [Color(hex: "4285F4"), Color(hex: "6C63FF")],
                startPoint: .leading,
                endPoint: .trailing
              )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
          }
          .disabled(isInitializing)
          .opacity(isInitializing ? 0.6 : 1)

          Button(action: onDelete) {
            Image(systemName: "trash")
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(.red)
              .frame(width: 46, height: 46)
              .background(
                RoundedRectangle(cornerRadius: 14)
                  .fill(Color.red.opacity(0.08))
              )
          }
        }

        Button(action: onSelectQuiz) {
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
        .disabled(isInitializing)
        .opacity(isInitializing ? 0.6 : 1)
      }

    case .notDownloaded, .failed:
      Button(action: onDownload) {
        HStack {
          Image(systemName: "arrow.down.circle.fill")
          Text("Download")
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(
          LinearGradient(
            colors: [Color(hex: "4285F4"), Color(hex: "6C63FF")],
            startPoint: .leading,
            endPoint: .trailing
          )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
      }

    case .downloading:
      EmptyView()
    }
  }
}
