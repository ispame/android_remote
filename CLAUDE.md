# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**OpenClaw Remote** - A cross-platform mobile app (iOS + Android) for remote controlling OpenClaw robots via WebSocket. Supports voice and text input.

## Architecture

**Kotlin Multiplatform (KMP) + Compose Multiplatform**

- `shared/` - All shared business logic, UI, and platform abstractions
- `androidApp/` - Android-specific implementation
- `iosApp/` - iOS-specific implementation

### Shared Module Structure

```
shared/src/
├── commonMain/kotlin/com/openclaw/remote/
│   ├── data/          # ChatMessage, GatewayConfig, SettingsManager (expect)
│   ├── domain/        # ConnectionState, PairingState enums
│   ├── network/       # WebSocketManager (Ktor-based)
│   ├── viewmodel/      # ChatViewModel
│   ├── audio/         # AudioRecorder (expect/actual)
│   └── ui/
│       ├── theme/     # MochiColors, Theme (warm cream/ink black)
│       └── screen/    # MainScreen, MessageBubble, SettingsScreen, QRParse
├── androidMain/       # Android-specific actual implementations
└── iosMain/          # iOS-specific actual implementations
```

## Build Commands

### Android

```bash
./gradlew :androidApp:assembleDebug
```

### iOS (requires macOS with Xcode)

```bash
# Generate Xcode framework
./gradlew :shared:embedAndSignAppleFrameworkForXcode

# Open in Xcode and run
cd iosApp/OpenClawRemote
pod install
open OpenClawRemote.xcworkspace
```

## Key Technologies

- **Kotlin 1.9.22** with KMP
- **Compose Multiplatform 2.0.0** for UI
- **Ktor Client 2.3.7** for WebSocket (cross-platform)
- **Kotlinx Serialization** for JSON
- **DataStore** (Android) / **NSUserDefaults** (iOS) for persistence

## Platform-Specific Implementations

| Component | Android | iOS |
|-----------|---------|-----|
| WebSocket | Ktor OKHttp | Ktor Darwin |
| Settings | DataStore | NSUserDefaults |
| Audio | MediaRecorder | AVAudioRecorder |
| QR Scanner | CameraX + ZXing | AVFoundation |
| UI | Compose | Compose |

## Theme

Warm cream (light) / Pure ink black (dark) - MochiColors system with陶土棕 (terracotta) accents.
