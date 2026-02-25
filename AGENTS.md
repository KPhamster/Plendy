# AGENTS.md

## Cursor Cloud specific instructions

### Environment

- **Flutter SDK** is installed at `/opt/flutter_install/flutter/bin` and added to `PATH` via `~/.bashrc`.
- **Node.js 22** is pre-installed (required for Firebase Cloud Functions in `functions/`).
- The app targets **web** for development in this environment (no Android SDK or Xcode available). Use `flutter run -d web-server --web-port=8080 --web-hostname=0.0.0.0` to start the dev server.

### Placeholder config files

Several files are gitignored and must be created from templates before the app compiles:

| File | Source |
|------|--------|
| `lib/config/api_keys.dart` | Copy from `lib/config/api_keys.template.dart` |
| `lib/config/api_secrets.dart` | Copy from `lib/config/api_secrets.template.dart`, then add missing fields: `geminiApiKey`, `facebookAppId`, `facebookAppSecret`, `facebookAccessToken` |
| `.env` | Create with `GOOGLE_MAPS_API_KEY_WEB` and `GEMINI_API_KEY` |
| `web/index.html` | Standard Flutter web index with Firebase config from `lib/firebase_options.dart` |
| `android/app/google-services.json` | Minimal Firebase config (values from `firebase_options.dart`) |

The update script handles creating these placeholders automatically.

### Running the app

- **Web dev server**: `flutter run -d web-server --web-port=8080 --web-hostname=0.0.0.0`
- **Build web**: `flutter build web`
- **Tests**: `flutter test` (single placeholder test in `test/widget_test.dart`)
- **Lint**: `flutter analyze` — returns exit code 1 due to pre-existing `info`/`warning` level issues (mainly `avoid_print` and `deprecated_member_use`); there are no errors.
- **Cloud Functions lint**: `cd functions && npx eslint . --fix`

### Gotchas

- `api_secrets.dart` template is missing fields that the codebase references (`geminiApiKey`, `facebookAppId`, `facebookAppSecret`, `facebookAccessToken`). The update script creates the file with all required fields using placeholder values.
- `flutter analyze` exits non-zero due to ~3300 pre-existing lint warnings — this is normal for this codebase.
- The app connects to the live Firebase project `plendy-7df50`. Full end-to-end testing (login, data operations) requires valid Firebase credentials and API keys.
