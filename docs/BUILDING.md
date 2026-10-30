# Building

## Toolchain

- Flutter 3.47 (the version CI uses is in `.github/workflows/build.yml`).
- Android: Android SDK and Java 17.
- Windows: Visual Studio with "Desktop development with C++".

```sh
flutter pub get
dart run build_runner build -d     # regenerate database.g.dart after editing database.dart
flutter analyze
flutter test
```

## Running

```sh
flutter run -d windows
flutter run -d <android device id>
```

## Screenshots

`screenshots/screenshots_test.dart` fills an in-memory database with demo data and renders the main screens
on a phone and a desktop size, light and dark, into `screenshots/out/`:

```sh
flutter test screenshots --update-goldens
```

The demo data is made up; no real account or payment appears in the screenshots.

## Continuous integration

`.github/workflows/build.yml` runs on every push to `main`:

1. `flutter analyze` and `flutter test`.
2. Android APK (arm64) and a Windows zip.
3. Both are attached to a single release tagged `latest`.

`.github/workflows/keep-key.yml` runs twice a week so the cached Android signing key is not evicted.

## Signing Android builds

An installed Android app only accepts updates signed with the same key.

- **Default:** CI signs with a debug key kept in the Actions cache, so every build installs over the last.
- **Recommended for long-term use:** create your own release key and add it as repository secrets:

  | Secret | Value |
  | --- | --- |
  | `ANDROID_KEYSTORE_BASE64` | The `.jks` file, base64-encoded |
  | `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
  | `ANDROID_KEY_ALIAS` | Key alias |
  | `ANDROID_KEY_PASSWORD` | Key password |

  When `ANDROID_KEYSTORE_BASE64` is set, CI signs with it instead. Never commit the keystore or its passwords.
  Switching keys means uninstalling once (export your data or use sync first).
