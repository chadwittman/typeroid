# TypeRoid Security and Privacy Notes

TypeRoid is currently a personal-use macOS POC.

## What TypeRoid Sends

When you type the trigger, TypeRoid sends only the captured message before the trigger to the configured OpenAI Responses API endpoint.

TypeRoid does not intentionally send:

- Your API key in the prompt body.
- Debug status.
- Full clipboard history.
- Text outside the current captured message.

## Local Storage

- The OpenAI API key is stored in macOS Keychain.
- The trigger, model, menu behavior, and app exclusions are stored in local `UserDefaults`.
- Diagnostics show capture length, not captured message content.

## Runtime Guards

TypeRoid currently blocks or avoids:

- Secure/password-style text fields.
- Terminal, iTerm, and Warp by default.
- Likely browser address/search bars.

TypeRoid can also be disabled per app from the menu.

## Current Limitations

- The app is ad-hoc signed for local development, not Developer ID signed or notarized.
- Browser address-bar detection is heuristic and should be tested in each browser.
- App-specific text fields can behave differently depending on macOS Accessibility support.
- TypeRoid is not appropriate for secrets, passwords, medical/legal/financial sensitive content, or regulated customer data in its current POC form.

## Production Hardening Checklist

- Developer ID signing and notarization.
- Clear privacy policy and data handling disclosure.
- Explicit allowlist or stronger field-level controls for browsers and sensitive apps.
- Optional local-only mode or enterprise API-routing controls.
- Automated smoke tests for Notes, Slack, Chrome page fields, Mail, and Messages where feasible.
