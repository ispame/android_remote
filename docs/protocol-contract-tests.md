# Protocol Contract Tests

## Purpose

The V2 public protocol is owned by Router in
`android-remote-gateway/packages/protocol/fixtures/account-scoped-session-v2.json`.
Every client must decode the same fixture so Router, plugin-sdk, Boson plugins,
Android, and iOS cannot silently drift.

## Test Shape

- Router TS, plugin-sdk TS, and Boson plugin TS consume the Router protocol
  package or generated equivalent.
- Android reads the canonical fixture from the sibling
  `android-remote-gateway` checkout in
  `shared/src/androidUnitTest/kotlin/com/openclaw/remote/network/ProtocolFixtureContractTest.kt`.
- iOS reads the same fixture in
  `iosApp/OpenClawRemote/Tests/ProtocolFixtureContractTests.swift`.

Both mobile tests verify:

- the fixture frame list and order are stable
- every frame decodes with the platform JSON stack
- every frame encodes back to equivalent JSON
- old public identity fields are absent recursively:
  `device_id`, `app_id`, `client_id`, `from_app_id`, `target_app_id`,
  `target_id`, `from`, `to`
- key V2 fields exist for auth, registration, pairing, messages, ack,
  history pagination, and `session_preempted`

## Fixture Location

Default path resolution assumes these repositories are siblings:

```text
boson/
  android-remote-gateway/
  android_remote/
```

For CI or a different checkout layout, set:

```bash
export OPENCLAW_PROTOCOL_FIXTURE=/absolute/path/to/account-scoped-session-v2.json
```

## Commands

Android:

```bash
./gradlew :shared:testDebugUnitTest --tests com.openclaw.remote.network.ProtocolFixtureContractTest
```

iOS standalone Swift contract:

```bash
swiftc -parse-as-library iosApp/OpenClawRemote/Tests/ProtocolFixtureContractTests.swift -o /tmp/ProtocolFixtureContractTests
/tmp/ProtocolFixtureContractTests
```
