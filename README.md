# TypeRoid

Type like hell. Send like a pro.

TypeRoid is a macOS menu-bar POC that watches for `//`, grabs the current line/message, sends it to an API, and replaces it in-place with the same voice cleaned up.

## POC Scope

- Native Swift macOS menu-bar app.
- Global trigger, default `//`.
- Clipboard fallback replacement.
- OpenAI Responses API cleanup.
- One mode: fix spelling, grammar, punctuation, capitalization, and light clarity.
- No preview.
- Undo last replacement from the menu bar.

## Build

```bash
swift build
```

## Test

```bash
swift test
```

The current tests cover the OpenAI request shape, the "fix, don't rewrite" system instruction, and response parsing.

To build a menu-bar `.app` bundle:

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open build/TypeRoid.app
```

## Run

```bash
swift run TypeRoid
```

The first run needs macOS permissions:

1. Open System Settings.
2. Go to Privacy & Security > Accessibility.
3. Enable TypeRoid, Terminal, or the built executable, depending on how you launched it.
4. Go to Privacy & Security > Input Monitoring.
5. Enable TypeRoid, Terminal, or the built executable there too if macOS asks.
6. Relaunch TypeRoid.

Set your OpenAI API key from the menu-bar item before using `//`. The key is stored in your macOS Keychain. You can also change the trigger from the menu; `//` is the default.

Use `Test Cleanup API` from the menu to verify the API key and cleanup prompt before testing in a real text field.

To disable TypeRoid in one app, type in that app, open the TypeRoid menu, and choose `Exclude <App Name>`. Use `Clear App Exclusions` to reset the list.

## Current Replacement Strategy

The POC uses a clipboard fallback:

1. Detect `//`.
2. Delete the trigger.
3. Select from cursor to the beginning of the current paragraph/message with `Option+Shift+Up`, then fall back through `Cmd+Shift+Left` for single-line inputs.
4. Copy.
5. Clean via API.
6. Paste the replacement.

That is intentionally simple and works best in plain text fields. App-specific hardening should come next for Slack, Chrome, Mail, Messages, and Notes.

## Rewrite Contract

TypeRoid should not rewrite you into corporate assistant voice.

- Preserve voice and intent.
- Fix spelling, grammar, punctuation, capitalization.
- Do not add ideas.
- Do not add jargon.
- Do not over-polish.
- Keep directness and contractions.
