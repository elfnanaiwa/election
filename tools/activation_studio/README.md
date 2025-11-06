# Activation Studio

A small Flutter desktop app to generate activation codes for the Agenda application.

- Input: machine serial, expiry date (YYYY-MM-DD), and secret.
- Output: activation code = HMAC-SHA256(secret, `${serial}|${expiry}`) in hex.

## Run (Windows)

1. Install Flutter desktop support for Windows.
2. In this folder, run:
   - `flutter create .`  # generates Windows runner files if missing
   - `flutter pub get`
   - `flutter run -d windows`

## Build (Windows .exe)

- `flutter build windows`
- The executable will be under `build/windows/x64/runner/Release/activation_studio.exe`.

## Notes

- The secret must match the one baked in the main app. Keep it secure.
- Expiry must be formatted as `YYYY-MM-DD`.
