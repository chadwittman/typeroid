# TypeRoid Security & Privacy

TypeRoid is designed to be safe for daily use. Here's exactly what it does and doesn't do.

## What TypeRoid Sends

When you type `//` or `\\`, TypeRoid captures the relevant text and sends ONLY that text to your chosen AI provider (OpenAI, Anthropic, Google, or Groq).

**What gets sent:**
- The message you just typed (the text before the trigger)
- A system prompt telling the AI to clean/rewrite it

**What never gets sent:**
- Your API key in the message body (it's only in the auth header)
- Text from other apps or windows
- Clipboard history
- Your keystrokes (TypeRoid only watches for the trigger characters)
- Any telemetry, analytics, or usage data (there is none)

## Where Your Data Lives

| Data | Storage | Access |
|------|---------|--------|
| API keys | macOS Keychain (encrypted) | Only TypeRoid, protected by macOS |
| Settings (trigger, model, provider) | UserDefaults (local) | Only TypeRoid |
| Your text | Memory only, never saved | Discarded after replacement |

TypeRoid has **no database, no logs, no analytics, no crash reporting, no network calls** except the AI provider API when you trigger it.

## Permissions Explained

TypeRoid requires two macOS permissions:

### Accessibility
**What it does:** Reads the text field you're typing in and replaces text in place.
**Why it's needed:** This is how TypeRoid swaps your messy text for the cleaned version without copy/paste.
**What it can't do:** It only reads the focused text field. It cannot read other windows, other apps, or anything you haven't typed into.

### Input Monitoring
**What it does:** Watches keyboard input for the `//` and `\\` trigger sequences.
**Why it's needed:** TypeRoid needs to know when you type the trigger so it can activate.
**What it can't do:** TypeRoid uses a listen-only event tap. It cannot modify, block, or inject keystrokes. It only reads key events to match the trigger pattern. It does not log keystrokes.

## Safety Guards

TypeRoid will NOT activate in:
- **Password fields** (detected via Accessibility API secure text attributes)
- **Browser address bars** (heuristic detection for Safari, Chrome, Firefox, Edge, Brave)
- **Terminal apps** (Terminal, iTerm, Warp excluded by default)
- **Any app you manually exclude** from the menu

## What TypeRoid Does NOT Do

- Does not keylog. The keyboard monitor only maintains a tiny buffer (2-3 chars) to match the trigger, then clears it.
- Does not store or transmit your text anywhere except the single AI API call.
- Does not phone home. No analytics, no telemetry, no update checks.
- Does not run in the background when disabled. Toggle it off and it stops watching.
- Does not modify system files, install kernel extensions, or require root access.

## API Key Security

- Keys are stored in macOS Keychain using `kSecClassGenericPassword`
- Each provider has its own Keychain entry (`openai_api_key`, `anthropic_api_key`, etc.)
- Keys are transmitted only in HTTPS Authorization headers (Bearer token) or provider-specific auth headers
- Keys are never logged, printed to console, or included in error messages

## Open Source Transparency

TypeRoid is fully open source. Every line of code is auditable:

- `TextCleaner.swift` - All network calls. You can verify exactly what's sent.
- `TriggerMonitor.swift` - The keyboard monitor. You can verify it only matches triggers.
- `KeychainStore.swift` - Keychain operations. Standard Apple Security framework.
- `AccessibilityReplacement.swift` - How text is read and replaced.
- `ClipboardReplacement.swift` - The clipboard fallback method.

## Known Limitations

- Ad-hoc signed (not notarized). macOS will warn on first open. Right-click > Open to bypass.
- Browser address bar detection is heuristic. Report false positives.
- Some apps don't expose text via Accessibility API. TypeRoid falls back to clipboard method.
- The clipboard fallback briefly uses your clipboard (saves and restores it).

## Responsible Disclosure

Found a security issue? Open a GitHub issue or email [add your email].
