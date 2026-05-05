# LifeOS

[![Flutter](https://img.shields.io/badge/Flutter-stable-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%5E3.11-0175C2?logo=dart)](https://dart.dev)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey)]()

**LifeOS** is a cross-platform personal productivity client built with [Flutter](https://flutter.dev). It connects a GitHub repository as the source of truth for diary entries, saved items, and habit check-ins, with optional OpenAI-compatible LLM endpoints for assisted tagging and naming.

<img width="1923" height="818" alt="cover-lifeos-v1" src="https://github.com/user-attachments/assets/7993da90-d09f-4fa6-80b3-00790cdc37db" />

---

## Table of contents

- [Features](#features)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Getting started](#getting-started)
- [Configuration](#configuration)
- [Building for production](#building-for-production)
- [Continuous integration](#continuous-integration)
- [Contributing](#contributing)
- [Security](#security)
- [License](#license)

---

## Features

| Area | Description |
|------|-------------|
| **Home** | Dashboard summarizing today’s diary and collect activity when GitHub is configured. |
| **Diary** | Markdown-backed diary stored and versioned via the GitHub Contents API; optional LLM-assisted tagging. |
| **Collect** | Curated captures in-repo with parsing and optional LLM-assisted file naming. |
| **Check-in** | Week-oriented check-in views and statistics backed by GitHub data. |
| **Settings** | GitHub personal access token, owner/repository, theme preference, LLM provider (OpenAI-compatible), base URL, model, and API key; local cache controls. |

Storage and secrets use platform-appropriate secure storage where applicable (`flutter_secure_storage`, `shared_preferences`).

---

## Architecture

- **UI:** [Material](https://docs.flutter.dev/ui/widgets/material) + [Forui](https://forui.dev/) for scaffold, navigation, and themed components.
- **Networking:** `http` for GitHub and LLM HTTP APIs.
- **Content:** `flutter_markdown_plus` for rendered markdown; `intl` for date formatting.

High-level flow: the app reads/writes structured content in a configured GitHub repository; LLM calls are optional and user-configured (base URL, model, key).

---

## Requirements

- [Flutter](https://docs.flutter.dev/get-started/install) (stable channel), compatible with **Dart ^3.11** as declared in [`pubspec.yaml`](pubspec.yaml).
- **iOS:** macOS, Xcode, CocoaPods (for native dependencies when building iOS).
- **Android:** Android SDK / Android Studio as per Flutter’s Android toolchain.

Run `flutter doctor` and resolve reported issues before building or running tests.

---

## Getting started

```bash
git clone <repository-url>
cd lifeos
flutter pub get
flutter run
```

Use `-d ios` or `-d android` to target a specific device or emulator.

### Run tests

```bash
flutter test
```

---

## Configuration

All sensitive values are entered in-app under **Settings** (not committed to the repository).

1. **GitHub**  
   - Create a [personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token) with repository access for the target repo.  
   - Set **owner** and **repository** name to match where diary, collect, and check-in data should live.

2. **LLM (optional)**  
   - Choose an OpenAI-compatible provider.  
   - Set **base URL**, **model**, and **API key** to match your deployment.  
   - User-configured base URLs may use `http://` during development; prefer **HTTPS** for production.

3. **Bundle / application IDs**  
   - iOS bundle identifier and Android `applicationId` are aligned (e.g. `com.lifeos.lifeos`). Adjust in Xcode / Gradle if you fork the project.

---

## Building for production

### iOS

- Open [`ios/Runner.xcworkspace`](ios/Runner.xcworkspace) in Xcode, select the **Runner** target, then **Signing & Capabilities**, and assign your **Team** for device runs and App Store archives.
- Simulator: `flutter run -d ios`
- Unsigned release artifact (e.g. for CI): `flutter build ios --no-codesign`

**App Transport Security:** [`ios/Runner/Info.plist`](ios/Runner/Info.plist) may allow arbitrary HTTP loads so that development LLM endpoints over `http://` work. Before App Store submission, tighten ATS (e.g. per-domain exceptions) when your hosts are known.

**CocoaPods:** A [`Podfile`](ios/Podfile) is maintained under `ios/`; `flutter build ios` / `flutter run` run `pod install` as needed.

### Android

```bash
flutter build apk
# or
flutter build appbundle
```

Configure signing in `android/app/build.gradle.kts` and your keystore per [Flutter’s Android deployment guide](https://docs.flutter.dev/deployment/android).

---

## Continuous integration

GitHub Actions workflow [`.github/workflows/ios.yml`](.github/workflows/ios.yml) runs on pushes and pull requests to `main` and `master`:

- `flutter pub get`
- `flutter test`
- `flutter build ios --no-codesign` on `macos-latest`

Extend with Android jobs if you need parity on CI.

---

## Contributing

Contributions are welcome.

1. Open an **issue** to describe a bug or proposal, or comment on an existing one.  
2. Fork the repository and create a **feature branch** from `main` (or the default branch).  
3. Keep changes focused; follow existing Dart style and [`analysis_options.yaml`](analysis_options.yaml).  
4. Run `flutter test` and ensure CI-relevant builds pass locally.  
5. Open a **pull request** with a clear description and, when applicable, screenshots for UI changes.

---

## Security

- **Do not** commit GitHub tokens, LLM API keys, or private repository URLs.  
- Rotate credentials if they are ever exposed.  
- For responsible disclosure of vulnerabilities, contact the maintainers privately (add contact details here when the project publishes them).

---

## License

This repository does not currently include a root-level `LICENSE` file. If you intend to distribute or accept external contributions under standard terms, add an explicit license (for example MIT or Apache-2.0) and update this section accordingly.

---

## Acknowledgements

- [Flutter](https://flutter.dev) and the Dart team  
- [Forui](https://forui.dev/)  
- [GitHub REST API](https://docs.github.com/en/rest)
