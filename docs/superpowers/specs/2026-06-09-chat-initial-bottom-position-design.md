# Chat Initial Bottom Position Design

## Goal

Make iOS and Android conversations behave like WeChat: opening an existing
conversation shows the newest message immediately instead of starting near the
oldest loaded message.

## Scope

- iOS Agent conversations.
- iOS AI Provider conversations.
- Android Agent conversations.
- Initial entry and Agent/profile switching.
- Existing automatic scrolling when new messages arrive.
- Existing older-history pagination behavior.

This change does not redesign message ordering, history storage, or navigation.

## Behavior

1. When a conversation with existing messages first becomes visible, position
   the list at its bottom without animation.
2. When the active Agent/profile changes, position the newly selected
   conversation at its bottom after its messages are laid out.
3. When a new message arrives:
   - Follow it when the user is already near the bottom.
   - Follow it when the newest message was sent by the user.
   - Do not move the viewport when the user is reading older messages.
4. When older history is prepended, preserve the current reading position.
5. Empty conversations remain at their normal empty state.

## Implementation

### iOS

`MainScreenView` keeps the existing chronological `ScrollView` and bottom
anchor. It performs a one-time, non-animated `scrollTo` after the view appears
and after a profile switch has supplied the selected profile's messages. The
existing animated new-message follow behavior remains guarded by the
near-bottom and user-message conditions.

`ProviderChatScreen` uses the same bottom-anchor rule on first appearance.
Changes to the local record list continue to scroll to the newest record.

The initial positioning state is scoped to each visible conversation so
returning from the Agent list positions the reopened chat at the newest
message.

### Android

`MainScreen` keeps the existing chronological `LazyColumn`. A conversation
identity key based on the selected profile controls initial positioning. Once
messages for that identity are available and the list has been measured, the
list performs a non-animated `scrollToItem` to the final message.

The existing animated follow behavior remains for new messages when the user
is near the bottom or sent the newest message. Prepending history must not
re-run initial positioning.

## Testing

- Add focused regression tests for the platform-independent initial-scroll
  decision/state where practical.
- Add source-level layout regression assertions where the current native UI
  test setup cannot instantiate `ScrollViewReader` or `LazyColumn`.
- Run the iOS test target or its repository test harness.
- Run Android unit tests and a debug build.
- Build and launch the iOS app in Simulator, then verify a long Agent
  conversation opens at the newest message.
- Verify Android compilation and, when a runnable emulator/device is
  available, open a long conversation and confirm the same behavior.

## Acceptance Criteria

- Opening a long existing conversation shows its latest message immediately on
  both platforms.
- Switching Agents shows the selected Agent's latest message.
- No visible animated journey from the oldest message to the newest message on
  entry.
- Reading older messages is not interrupted by incoming assistant messages.
- Sending a message returns or keeps the view at the bottom.
- Loading older history does not jump back to the newest message.
