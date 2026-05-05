# lifeos

A new Flutter project.

## iOS

- Build and run require **macOS** with **Xcode** and **CocoaPods** (`sudo gem install cocoapods` if needed). Run `flutter doctor` and fix any iOS toolchain warnings.
- Bundle ID is `com.lifeos.lifeos` (matches Android `applicationId`). Open `ios/Runner.xcworkspace` in Xcode, select the **Runner** target, **Signing & Capabilities**, and choose your **Team** for device runs and archives.
- Simulator: `flutter run -d ios`. Release build without signing: `flutter build ios --no-codesign`.
- CocoaPods: [`ios/Podfile`](ios/Podfile) is checked in; `flutter build ios` / `flutter run` run `pod install` as needed.
- **App Transport Security**: `Info.plist` allows arbitrary HTTP loads so user-configured LLM base URLs can use `http://`. Prefer HTTPS in production; tightening ATS (per-domain exceptions) is recommended before App Store submission if you can scope known hosts.
- **CI**: [`.github/workflows/ios.yml`](.github/workflows/ios.yml) runs `flutter test` and `flutter build ios --no-codesign` on `macos-latest` (requires GitHub-hosted Xcode).

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.