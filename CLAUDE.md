# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**OpenClaw Remote** - A cross-platform mobile app (iOS + Android) for remote controlling OpenClaw robots via WebSocket. Supports voice and text input.

## Architecture

**Android: Kotlin + Jetpack Compose | iOS: Swift + SwiftUI**

Android and iOS maintain fully independent UI codebases. The KMP `shared/` module provides only **data models, network, audio, and domain logic** — no UI.

```
androidApp/src/main/kotlin/com/openclaw/remote/
├── MainActivity.kt
└── ui/
    ├── theme/           # MochiColors (warm cream / ink black)
    └── screen/          # MainScreen, SettingsScreen, MessageBubble, QRScannerScreen

iosApp/OpenClawRemote/Sources/
├── OpenClawRemoteApp.swift
├── MainScreenView.swift
├── SettingsScreenView.swift
├── MessageBubbleView.swift
├── InputAreaView.swift
├── QRScannerScreenView.swift
├── MochiColors.swift
└── ... (models, managers)

shared/src/
├── commonMain/kotlin/com/openclaw/remote/
│   ├── data/            # ChatMessage, GatewayConfig, SettingsManager (expect/actual)
│   ├── domain/          # ConnectionState, PairingState enums
│   ├── network/         # WebSocketManager (Ktor-based, expect/actual)
│   ├── viewmodel/       # ChatViewModel
│   └── audio/           # AudioRecorder (expect/actual)
├── androidMain/         # Android-specific implementations (DataStore, Ktor-OKHttp)
└── iosMain/            # iOS-specific implementations (NSUserDefaults, Ktor-Darwin)
```

## Build Commands

### Android

```bash
./gradlew :androidApp:assembleDebug
```

### iOS (requires macOS with Xcode)

```bash
# Regenerate Xcode project after shared code changes
./gradlew :shared:embedAndSignAppleFrameworkForXcode

# Open in Xcode and run
cd iosApp/OpenClawRemote
pod install
open OpenClawRemote.xcworkspace
```

## Key Technologies

| | Android | iOS |
|---|---|---|
| Language | Kotlin | Swift |
| UI | Jetpack Compose | SwiftUI |
| Network | Ktor OKHttp | Ktor Darwin |
| Settings | DataStore | NSUserDefaults |
| Audio | MediaRecorder | AVAudioRecorder |
| QR Scanner | CameraX + ZXing | AVFoundation |
| Serialization | Kotlinx Serialization | Codable (via shared model) |

## Theme — MochiColors

Warm cream (light) / Pure ink black (dark) — MochiColors system with terracotta accents.

**Light:**
- Background: `#FAF7F2` (warm cream)
- Primary: `#B85C38` (terracotta)
- Surface: `#FDFCF9`

**Dark:**
- Background: `#000000` (pure ink)
- Primary: `#C9884A` (warm amber)
- Surface: `#0D0D0D`

## Shared Module

The `shared/` module contains only platform-agnostic business logic:

- `ChatMessage`, `GatewayConfig` — data models
- `SettingsManager` — expect/actual for DataStore (Android) / NSUserDefaults (iOS)
- `WebSocketManager` — expect/actual for Ktor clients
- `AudioRecorder` — expect/actual for platform audio APIs
- `ChatViewModel` — message/pairing state management
- `ConnectionState`, `PairingState` — domain enums
