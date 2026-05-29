# Gemma4Chat

A native iOS app for chatting with local Gemma models using on-device inference. Built with SwiftUI and the LiteRTLM framework.

## Features

- **100% On-Device**: All inference runs locally on your iPhone/iPad — no cloud, no data leaves your device
- **Model Management**: Download, manage, and switch between multiple Gemma models
- **Streaming Responses**: Real-time token-by-token streaming with performance stats
- **Thinking Mode**: Visualize the model's chain-of-thought reasoning
- **Interactive Quiz Generation**: Paste any source text (essays, articles, notes) and Gemma 4 will dynamically compile a custom 10-question multiple-choice quiz. Play through it in a premium glassmorphic slide-deck view with haptic feedback and scored celebration views.
- **Beautiful UI**: Google-inspired design with gradient accents, custom chat bubbles, and smooth animations

## Architecture

```
Gemma4Chat/
├── Gemma4ChatApp.swift          # App entry point
├── Models/
│   ├── ChatMessage.swift         # Chat message data model
│   ├── GemmaModel.swift          # Model definitions (URLs, params)
│   └── InferenceStats.swift      # Performance statistics
├── Services/
│   ├── LLMInferenceService.swift # LiteRTLM engine wrapper
│   └── ModelDownloader.swift     # HuggingFace model downloader
├── ViewModels/
│   └── ChatViewModel.swift       # Chat state & streaming logic
├── Views/
│   ├── RootView.swift            # Navigation root
│   ├── ModelSelectionView.swift   # Model browser/download screen
│   ├── ChatView.swift            # Main chat interface
│   └── MessageBubble.swift       # Chat bubble components
└── Extensions/
    └── Color+Hex.swift           # Color utilities
```

## Dependencies

This app uses **LiteRTLM** — Google's Swift SDK for on-device LLM inference. The SDK provides:
- `Engine` / `EngineConfig` — Model loading and backend selection (CPU/GPU)
- `Conversation` / `ConversationConfig` — Multi-turn chat session management
- `SamplerConfig` — Temperature, TopK, TopP sampling parameters
- Streaming responses via `sendMessageStream()`

### Adding the LiteRTLM Dependency

The LiteRTLM Swift package is distributed internally. To set it up:

1. Open `Gemma4Chat.xcodeproj` in Xcode
2. Go to **File → Add Package Dependencies**
3. Add the LiteRTLM Swift package URL provided by the AI Edge team
4. Select the `LiteRTLM` product and add it to the `Gemma4Chat` target

> **Alternative**: If using the MediaPipe `LlmInference` API instead of LiteRTLM, 
> you can add `MediaPipeTasksGenAI` from:
> `https://github.com/nicklama/mediapipe-genai-ios`

## Building

1. Open `Gemma4Chat.xcodeproj` in Xcode 16+
2. Add the LiteRTLM package dependency (see above)
3. Select your development team under Signing & Capabilities
4. Build and run on a physical iOS device (iOS 17+)

> **Note**: Simulator support is limited — GPU acceleration requires a physical device.

## Supported Models

| Model | Size | Description |
|-------|------|-------------|
| Gemma 4 E4B | ~3.6 GB | Next-generation high-performance local model with full native chain-of-thought reasoning |
| Gemma 4 E2B | ~2.5 GB | Next-generation compact local model with native chain-of-thought reasoning |

Models are downloaded from Google AI Edge Gallery CDN on first use and stored locally.

## Design Patterns

This app follows patterns from the [AI Edge Gallery](https://github.com/google-ai-edge/gallery) reference implementation:

- **Engine Provider Pattern**: `LLMInferenceService` wraps LiteRTLM's `Engine` and `Conversation` lifecycle
- **Streaming Buffer**: 200ms buffered UI updates on iOS to preserve CPU & battery
- **Conversation Reset**: Proper cleanup ordering (conversation before engine) to prevent crashes
- **Download Delegate**: `URLSessionDownloadDelegate` with progress tracking for large model files

## License

Apache 2.0
