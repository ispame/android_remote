# Chat Initial Bottom Position Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open existing iOS and Android conversations at their newest message while preserving current history-reading and new-message follow behavior.

**Architecture:** Keep both message lists in chronological order and retain their existing bottom detection. Add conversation-scoped initial-position state so each chat performs one non-animated bottom jump after content is available; subsequent messages continue through the existing guarded animated-follow path.

**Tech Stack:** SwiftUI 5.9 on iOS 15+, Jetpack Compose, Kotlin/JUnit 4, Gradle, XcodeBuildMCP.

---

### Task 1: iOS Initial Conversation Position

**Files:**
- Modify: `iosApp/OpenClawRemote/Tests/AgentNavigationLayoutTests.swift`
- Modify: `iosApp/OpenClawRemote/Sources/MainScreenView.swift:327-474`
- Modify: `iosApp/OpenClawRemote/Sources/Views/AgentsTabView.swift:300-455`

- [ ] **Step 1: Write the failing iOS source regression test**

Add a test that reads `MainScreenView.swift` and `AgentsTabView.swift` and asserts:

```swift
try expect(
    mainScreen.contains(".onAppear {") &&
        mainScreen.contains("positionAtChatBottomIfNeeded"),
    "Agent chat should position at the newest message when it first appears"
)
try expect(
    mainScreen.contains(".onChange(of: settingsManager.selectedProfileId)"),
    "Agent chat should reposition when the selected Agent changes"
)
try expect(
    providerChat.contains("positionProviderChatAtBottom"),
    "Provider chat should position at the newest local record when it first appears"
)
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
swiftc -parse-as-library iosApp/OpenClawRemote/Tests/AgentNavigationLayoutTests.swift \
  -o /tmp/AgentNavigationLayoutTests &&
/tmp/AgentNavigationLayoutTests
```

Expected: FAIL with the Agent-chat initial-position assertion because the positioning helpers do not exist.

- [ ] **Step 3: Add non-animated initial positioning to Agent chat**

In `MainScreenView`, add conversation-scoped state:

```swift
@State private var initiallyPositionedProfileId: String?
```

Inside the `ScrollViewReader`, add first-appearance and profile-change hooks:

```swift
.onAppear {
    positionAtChatBottomIfNeeded(proxy: proxy)
}
.onChange(of: settingsManager.selectedProfileId) { _ in
    positionAtChatBottomIfNeeded(proxy: proxy)
}
```

Update the last-message handler so an unpositioned conversation jumps without animation before normal follow logic:

```swift
if initiallyPositionedProfileId != settingsManager.selectedProfileId {
    positionAtChatBottomIfNeeded(proxy: proxy)
} else if isNearChatBottom || lastMessage.isUser {
    withAnimation(.easeOut(duration: 0.2)) {
        proxy.scrollTo(bottomAnchorId, anchor: .bottom)
    }
}
```

Add the helper:

```swift
private func positionAtChatBottomIfNeeded(proxy: ScrollViewProxy) {
    let profileId = settingsManager.selectedProfileId
    guard initiallyPositionedProfileId != profileId,
          !wsManager.messages.isEmpty else {
        return
    }
    DispatchQueue.main.async {
        guard settingsManager.selectedProfileId == profileId,
              !wsManager.messages.isEmpty else {
            return
        }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            proxy.scrollTo(bottomAnchorId, anchor: .bottom)
        }
        initiallyPositionedProfileId = profileId
    }
}
```

- [ ] **Step 4: Add non-animated initial positioning to Provider chat**

Inside `ProviderChatScreen`:

```swift
@State private var hasPositionedInitialRecords = false

.onAppear {
    positionProviderChatAtBottom(proxy: proxy)
}
```

Add:

```swift
private func positionProviderChatAtBottom(proxy: ScrollViewProxy) {
    guard !hasPositionedInitialRecords, !records.isEmpty else { return }
    DispatchQueue.main.async {
        guard !hasPositionedInitialRecords, !records.isEmpty else { return }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            proxy.scrollTo(bottomAnchorId, anchor: .bottom)
        }
        hasPositionedInitialRecords = true
    }
}
```

Keep the existing animated `records.count` behavior for messages appended after entry.

- [ ] **Step 5: Run the iOS regression test to verify GREEN**

Run the command from Step 2.

Expected: `AgentNavigationLayoutTests passed`.

- [ ] **Step 6: Review the iOS diff without staging unrelated work**

```bash
git diff --check -- \
  iosApp/OpenClawRemote/Tests/AgentNavigationLayoutTests.swift \
  iosApp/OpenClawRemote/Sources/MainScreenView.swift \
  iosApp/OpenClawRemote/Sources/Views/AgentsTabView.swift
```

Expected: no whitespace errors. Do not commit these files automatically because
`AgentsTabView.swift` already contains user changes unrelated to this task.

### Task 2: Android Initial Conversation Position

**Files:**
- Create: `androidApp/src/test/kotlin/com/openclaw/remote/ui/screen/ChatInitialScrollTrackerTest.kt`
- Modify: `androidApp/src/main/kotlin/com/openclaw/remote/ui/screen/MainScreen.kt:113-163`

- [ ] **Step 1: Write the failing Android unit test**

Create:

```kotlin
package com.openclaw.remote.ui.screen

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatInitialScrollTrackerTest {
    @Test
    fun emptyConversationWaitsForMessagesBeforePositioning() {
        val tracker = ChatInitialScrollTracker()

        assertFalse(tracker.shouldPosition("agent-1", hasMessages = false))
        assertTrue(tracker.shouldPosition("agent-1", hasMessages = true))
    }

    @Test
    fun positionedConversationDoesNotRepositionForIncomingMessages() {
        val tracker = ChatInitialScrollTracker()

        assertTrue(tracker.shouldPosition("agent-1", hasMessages = true))
        tracker.markPositioned("agent-1")

        assertFalse(tracker.shouldPosition("agent-1", hasMessages = true))
    }

    @Test
    fun switchingConversationRequiresNewInitialPosition() {
        val tracker = ChatInitialScrollTracker()
        tracker.markPositioned("agent-1")

        assertTrue(tracker.shouldPosition("agent-2", hasMessages = true))
    }
}
```

- [ ] **Step 2: Run the Android test to verify RED**

Run:

```bash
./gradlew :androidApp:testDebugUnitTest \
  --tests com.openclaw.remote.ui.screen.ChatInitialScrollTrackerTest
```

Expected: compilation FAIL because `ChatInitialScrollTracker` does not exist.

- [ ] **Step 3: Implement the tracker and initial direct scroll**

Add near `MainScreen`:

```kotlin
internal class ChatInitialScrollTracker {
    private var positionedConversationId: String? = null

    fun shouldPosition(conversationId: String, hasMessages: Boolean): Boolean {
        return hasMessages && positionedConversationId != conversationId
    }

    fun markPositioned(conversationId: String) {
        positionedConversationId = conversationId
    }

    fun isPositioned(conversationId: String): Boolean {
        return positionedConversationId == conversationId
    }
}
```

Remember it with the list state:

```kotlin
val initialScrollTracker = remember { ChatInitialScrollTracker() }
```

Before the animated new-message effect, add:

```kotlin
LaunchedEffect(selectedProfileId, lastMessageKey) {
    if (!initialScrollTracker.shouldPosition(
            conversationId = selectedProfileId,
            hasMessages = messages.isNotEmpty(),
        )
    ) {
        return@LaunchedEffect
    }
    withFrameNanos { }
    while (listState.layoutInfo.totalItemsCount == 0) {
        withFrameNanos { }
    }
    listState.scrollToItem(listState.layoutInfo.totalItemsCount - 1)
    initialScrollTracker.markPositioned(selectedProfileId)
}
```

Guard the existing animated effect:

```kotlin
if (!initialScrollTracker.isPositioned(selectedProfileId)) {
    return@LaunchedEffect
}
```

This prevents the initial history from animating from the top while preserving animated follow for later messages.

- [ ] **Step 4: Run the Android test to verify GREEN**

Run the command from Step 2.

Expected: three tests PASS.

- [ ] **Step 5: Run adjacent Android UI-state tests**

Run:

```bash
./gradlew :androidApp:testDebugUnitTest \
  --tests 'com.openclaw.remote.ui.screen.*'
```

Expected: all screen package unit tests PASS.

- [ ] **Step 6: Review the Android diff**

```bash
git diff --check -- \
  androidApp/src/main/kotlin/com/openclaw/remote/ui/screen/MainScreen.kt \
  androidApp/src/test/kotlin/com/openclaw/remote/ui/screen/ChatInitialScrollTrackerTest.kt
```

Expected: no whitespace errors. Keep implementation uncommitted with the iOS
change so the user can review the complete cross-platform patch together.

### Task 3: Cross-Platform Verification

**Files:**
- Verify: `iosApp/OpenClawRemote/OpenClawRemote.xcworkspace`
- Verify: `androidApp`

- [ ] **Step 1: Run focused iOS tests**

```bash
swiftc -parse-as-library iosApp/OpenClawRemote/Tests/AgentNavigationLayoutTests.swift \
  -o /tmp/AgentNavigationLayoutTests &&
/tmp/AgentNavigationLayoutTests
```

Expected: PASS.

- [ ] **Step 2: Build Android**

```bash
./gradlew :androidApp:assembleDebug
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 3: Build and launch iOS in Simulator**

Use XcodeBuildMCP:

1. Show session defaults.
2. List simulators and select a booted iPhone, or boot one when none is available.
3. Set `workspacePath` to `iosApp/OpenClawRemote/OpenClawRemote.xcworkspace`.
4. Set scheme `OpenClawRemote`.
5. Build and run.

Expected: build succeeds and the app launches.

- [ ] **Step 4: Verify the iOS interaction**

Open an Agent with enough history to exceed one screen. Confirm:

- The newest message is visible immediately.
- There is no animated journey from the oldest message.
- Scrolling upward and receiving an assistant message does not force the view down.
- Sending a message returns the view to the bottom.

- [ ] **Step 5: Review the final diff**

```bash
git diff --check HEAD~2..HEAD
git status --short
```

Expected: no whitespace errors; only planned files plus pre-existing user changes remain.
