# TypeRoid

Type like hell. Send like a pro.

TypeRoid is a macOS menu-bar POC that watches for `//`, grabs the current line/message, sends it to an API, and replaces it in-place with the same voice cleaned up.

## POC Scope

- Native Swift macOS menu-bar app.
- Global trigger, default `//`.
- Accessibility-based replacement first, with clipboard fallback for apps that do not expose editable text.
- OpenAI Responses API cleanup.
- Default model: `gpt-4.1-nano` for low latency and low cost.
- One mode: fix spelling, grammar, punctuation, capitalization, and light clarity.
- No preview.
- Undo last replacement from the menu bar.
- API self-test from the menu bar.
- Per-app exclusions.
- Rewrite pipeline diagnostics for capture/API/replacement debugging.

## Build

```bash
swift build
```

## Test

```bash
swift test
```

The current tests cover the OpenAI request shape, the "fix, don't rewrite" system instruction, response parsing, trigger stripping, current-message extraction, Accessibility replacement planning, and app exclusion settings.

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

If the debug status shows `Monitor: blocked` or `Accessibility trusted: no`, run:

```bash
./scripts/reset-permissions.sh
```

Then remove/re-add `/Users/chaztyler/TypeRoid/build/TypeRoid.app` in both Accessibility and Input Monitoring before relaunching.

Set your OpenAI API key from the menu-bar item before using `//`. The key is stored in your macOS Keychain. You can also change the trigger from the menu; `//` is the default.

Use `Test Cleanup API` from the menu to verify the API key and cleanup prompt before testing in a real text field.

To disable TypeRoid in one app, type in that app, open the TypeRoid menu, and choose `Exclude <App Name>`. Use `Clear App Exclusions` to reset the list.

Terminal, iTerm, and Warp are excluded by default so TypeRoid does not rewrite shell commands.

## Smoke Test

1. Relaunch the signed app bundle:

   ```bash
   pkill TypeRoid || true
   open ~/TypeRoid/build/TypeRoid.app
   ```

2. Choose `Test Cleanup API` from the TypeRoid menu. This verifies the API key, network call, model, and cleanup prompt.
3. In Notes, type:

   ```text
   hey john i saw the thing come through looks good but can we move meeting to tmrw im slammed today //
   ```

4. If it does not replace correctly, open the TypeRoid menu and read:
   - `Monitor`
   - `Last keys`
   - `Keys seen`
   - `Last rewrite`
   - `Captured`

Use `Copy Debug Status` to copy those fields to the clipboard. They separate keyboard monitoring, trigger detection, text capture, API cleanup, and replacement failures.

## Current Replacement Strategy

The POC uses Accessibility replacement first:

1. Detect `//`.
2. Read the focused text field through macOS Accessibility.
3. Find the current message before the last `//`.
4. Clean via API.
5. Replace that message and the trigger in-place.

If the focused app does not expose editable text through Accessibility, TypeRoid falls back to clipboard replacement:

1. Delete the trigger.
2. Select from cursor to the beginning of the current paragraph/message with `Option+Shift+Up`, then fall back through `Cmd+Shift+Left` for single-line inputs.
3. Copy.
4. Clean via API.
5. Paste the replacement.

That is intentionally simple and works best in plain text fields. App-specific hardening should come next for Slack, Chrome, Mail, Messages, and Notes.

## Rewrite Contract

TypeRoid should not rewrite you into corporate assistant voice.

- Preserve voice and intent.
- Fix spelling, grammar, punctuation, capitalization.
- Do not add ideas.
- Do not add jargon.
- Do not over-polish.
- Keep directness and contractions.
