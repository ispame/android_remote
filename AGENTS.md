# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

**OpenClaw Remote** — A cross-platform mobile app (iOS + Android) for remote-controlling OpenClaw robots via WebSocket. Supports voice and text input.

## Architecture

### Two Divergent iOS Implementations

**Android uses KMP shared module. iOS uses native SwiftUI.** The `shared/` KMP module exists but is **not imported by the iOS app** — the iOS app is fully standalone with its own implementations.

```
androidApp/          # Kotlin + Jetpack Compose (UI references shared/ module)
iosApp/              # SwiftUI (independent — NOT using shared/ KMP module)
shared/              # KMP module: shared by Android, NOT used by iOS
packages/plugin-sdk/ # TypeScript SDK: OpenClaw plugins → Router
```

This divergence is significant: all business logic is duplicated in two implementations. When changing WebSocket protocol, ASR flow, pairing, or history — edit both `shared/src/commonMain/.../WebSocketManager.kt` AND `iosApp/.../WebSocketManager.swift`.

### Android Architecture

- **UI**: Jetpack Compose in `androidApp/src/main/kotlin/`
- **Business logic**: `ChatViewModel` + `WebSocketManager` in `shared/src/commonMain/`
- **Platform bindings**: `WebSocketManagerAndroid.kt` (Ktor-OKHttp), `SettingsManagerAndroid.kt` (DataStore), `AudioRecorderAndroid.kt`
- **Entry point**: `MainActivity.kt` — owns `ChatViewModel` and wires UI state

### iOS Architecture (Native SwiftUI)

- **UI**: SwiftUI views in `iosApp/OpenClawRemote/Sources/`
- **Business logic**: `WebSocketManager.swift` (far more complex than Android — multi-profile, headset integration)
- **Settings**: `SettingsManager.swift` (NSUserDefaults-based, multi-profile)
- **Audio**: `AudioRecorder.swift` (AVAudioRecorder)
- **Headset subsystem**: `HeadsetAI/` directory — `HeadsetConversationController.swift`, `A9UltraBLEManager.swift`, `HeadsetAudio.swift`

### iOS Multi-Profile System

iOS supports **multiple agent profiles** simultaneously (`AgentProfile`, `AgentPlatform`). Each profile has its own gateway URL, backend ID, ASR config, and message history. `WebSocketManager` maintains per-profile state in `profileStates: [String: ProfileRuntimeState]`. Android has a single active gateway config.

### Plugin SDK (`packages/plugin-sdk`)

TypeScript package (`@openclaw/plugin-sdk`) for OpenClaw plugins to connect to the Router. Key files:

- `src/GatewayChannel.ts` — main class: ties together WebSocket, reconnect, heartbeat, HTTP callbacks
- `src/WsClient.ts` — raw WebSocket connection management
- `src/protocol/types.ts` — all JSON frame types (register, message, pair_request/response, ack, etc.)
- `src/protocol/serialize.ts` / `parse.ts` — JSON frame serialization
- `src/heartbeat.ts` — ping/pong heartbeat with dead-connection detection
- `src/reconnect.ts` — exponential backoff reconnection
- `src/http-client.ts` — HTTP callbacks: command result, event push

Protocol flow: Plugin registers as `client_type: "backend"` → receives `pair_request` from App → sends `pair_response(approve: true/false)` → bidirectional `message` frames.

## Build Commands

### Android

```bash
./gradlew :androidApp:assembleDebug
# Single test (if tests exist)
./gradlew :shared:jvmTest --tests "com.openclaw.remote.*"
```

### iOS (requires macOS + Xcode)

```bash
# Regenerate Xcode project after shared code changes (not needed for iOS native edits)
./gradlew :shared:embedAndSignAppleFrameworkForXcode

# In Xcode:
cd iosApp/OpenClawRemote && pod install && open OpenClawRemote.xcworkspace
```

Note: `iosApp` is commented out in `settings.gradle.kts` — the iOS project is managed entirely by its own `.xcworkspace`.

### Plugin SDK

```bash
cd packages/plugin-sdk
pnpm install
pnpm build       # TypeScript → dist/
pnpm test        # vitest run
pnpm test:watch  # vitest (watch mode)
```

## WebSocket Protocol (App ↔ Router)

App connects as `client_type: "app"`, plugin as `client_type: "backend"`.

Key message types:
- `register` → `registered` (success/fail)
- `pair_request` → `pair_response { approve: bool }` — App requests pairing with backend
- `message` — bidirectional text or audio; audio includes `asr` config with `mode: "router"|"backend"`
- `asr_result` — router forwards ASR transcription result ( correlates via `client_message_id`)
- `ack` — App acks received message (Router tracks delivery)
- `history_request` → `history_response` — paginated chat history
- `ping`/`pong` — heartbeat
- `unpair` — teardown pairing

QR code format: `openclaw://connect?gateway=<url>&backendId=<id>&token=<t>` or JSON `{"gateway": "...", "backendId": "...", ...}`.

## Key Technologies

| | Android | iOS |
|---|---|---|
| UI | Jetpack Compose | SwiftUI |
| Network | Ktor OKHttp | URLSession WebSocket |
| Settings | DataStore | NSUserDefaults |
| Audio | MediaRecorder | AVAudioRecorder |
| QR Scanner | CameraX + ZXing | AVFoundation |
| Message models | Kotlinx Serialization | Codable |

## Theme — MochiColors

Warm cream (light) / Pure ink black (dark) — terracotta/amber accents.

**Light:** Background `#FAF7F2`, Primary `#B85C38` (terracotta)
**Dark:** Background `#000000` (pure ink), Primary `#C9884A` (warm amber)


## 连接A9耳机的文档在路径
/Users/spame/WorkTable/openclaw_coder/boson/android_remote/docs/ble