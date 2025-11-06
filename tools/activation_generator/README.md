# Activation Code Generator (CLI)

Generates activation codes for the Agenda desktop app.

Formula:
- payload: `SERIAL|YYYY-MM-DD`
- code: `HMAC-SHA256(secret, payload)` as lowercase hex

IMPORTANT: Use the exact same secret as in the app (`_generateActivationFor`). Change it once for production.

## Usage

From this folder run:

```powershell
# Install deps
dart pub get

# Run with args
dart run bin/activation_generator.dart --serial YOUR_SERIAL --expiry 2026-09-19 --secret YOUR_SECRET

# Or via stdin prompts
dart run bin/activation_generator.dart
```

Output:
- Prints the activation code; copy it back to the user.

Notes:
- Expiry must be a date only (YYYY-MM-DD), the app compares by date part.
