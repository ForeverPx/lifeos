# LifeOS

[简体中文](README.zh-CN.md) | [English](README.md)

[Flutter](https://flutter.dev)
[Dart](https://dart.dev)
[Platform]()

**LifeOS** 是一个基于 [Flutter](https://flutter.dev) 的跨平台个人效率客户端。它将一个 GitHub 仓库作为“唯一事实来源（source of truth）”来存储日记、收藏与打卡数据；同时支持（可选）配置 OpenAI 兼容的大模型接口，用于辅助日记打标签、收藏文件命名等。

---

## 目录

- [功能特性](#功能特性)
- [架构](#架构)
- [数据仓库目录约定](#数据仓库目录约定)
- [环境要求](#环境要求)
- [快速开始](#快速开始)
- [配置说明](#配置说明)
- [生产构建](#生产构建)
- [持续集成](#持续集成)
- [参与贡献](#参与贡献)
- [安全](#安全)
- [许可证](#许可证)

---

## 功能特性


| 模块     | 说明                                                                             |
| ------ | ------------------------------------------------------------------------------ |
| **首页** | 在完成 GitHub 配置后，汇总今天的日记与收藏动态。                                                   |
| **日记** | 基于 Markdown 的日记，使用 GitHub Contents API 存储与版本管理；可选大模型辅助打标签。                     |
| **收藏** | 将内容按天归档进仓库，支持解析与（可选）大模型辅助命名。                                                   |
| **打卡** | 以“周”为粒度的打卡视图与统计，数据存储在 GitHub。                                                  |
| **设置** | GitHub Token、owner/repo、主题偏好、大模型（OpenAI 兼容）base URL / model / API key、本地缓存清理等。 |


在本地存储与敏感信息方面，应用会尽量使用平台适配的安全存储方案（如 `flutter_secure_storage`、`shared_preferences`）。

---

## 架构

- **UI**：Flutter Material + [Forui](https://forui.dev/)（脚手架、导航与主题组件）
- **网络**：`http` 请求 GitHub 与大模型 HTTP API
- **内容渲染**：`flutter_markdown_plus` 渲染 Markdown；`intl` 做日期格式化

整体流程：应用读取/写入一个用户配置的 GitHub 仓库中的结构化内容；大模型调用完全可选，并由用户在设置里自行配置（base URL、model、key）。

---

## 数据仓库目录约定

LifeOS 通过 GitHub **Contents API** 在你配置的仓库里读写数据。应用默认使用（并在需要时自动创建）如下路径约定：

### 日记（Diary）

- 日记正文：`daily_notes/<YYYY>/<MM>/<DD>.md`
  - 读取时也兼容同目录下的：`D.md`、`DD.md`、`YYYY-MM-DD.md`、以及 `DD-*.md` / `DD_*.md` 等命名方式
- 日记图片：`daily_notes/media/<可选子目录>/<文件名>`

### 收藏（Collect）

- 按天目录：`collect/<YYYY-MM-DD>/`
- 文本文件：`collect/<YYYY-MM-DD>/*.md`（也允许 `.markdown` / `.txt`）
- 收藏图片：`collect/media/<可选子目录>/<文件名>`

### 打卡（Check-in）

- 周打卡文件：`checkins/<weekId>/checkin.json`
- 打卡汇总统计：`checkins/_global_checkin_stats.json`

如果你使用一个全新的空仓库，也无需提前手动创建目录：首次保存时应用会自动创建相应文件/目录。

---

## 环境要求

- [Flutter](https://docs.flutter.dev/get-started/install)（stable 渠道），Dart 版本需满足 `[pubspec.yaml](pubspec.yaml)` 中的 **Dart ^3.11**
- **iOS**：macOS、Xcode、CocoaPods（iOS 依赖）
- **Android**：Android SDK / Android Studio（按 Flutter Android 工具链要求）

建议先运行 `flutter doctor`，并解决其中提示的问题。

---

## 快速开始

```bash
git clone <repository-url>
cd lifeos
flutter pub get
flutter run
```

使用 `-d ios` 或 `-d android` 指定设备/模拟器。

### 运行测试

```bash
flutter test
```

---

## 配置说明

所有敏感信息都在应用内 **Settings / 设置** 中填写（不会写入/提交到本仓库）。

1. **GitHub**
  - 创建一个可访问目标仓库的 [personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)
  - 在设置里填写 **owner** 与 **repository**（用于存放日记、收藏、打卡数据的仓库）
  - 建议使用 **fine-grained PAT**，并只对单个仓库授权，同时授予 **Contents** 与 **Metadata** 的读/写权限
2. **大模型（可选）**
  - 选择 OpenAI 兼容形态
  - 配置 **base URL**、**model**、**API key**
  - 开发期可使用 `http://`；生产环境建议使用 **HTTPS**
3. **Bundle / Application ID**
  - iOS bundle id 与 Android `applicationId` 目前保持一致（例如 `com.lifeos.lifeos`）。如你 fork 作为自己的应用分发，请在 Xcode / Gradle 中调整。

---

## 生产构建

### iOS

- 用 Xcode 打开 `[ios/Runner.xcworkspace](ios/Runner.xcworkspace)`，在 **Signing & Capabilities** 里选择你的 **Team**，用于真机调试与打包归档
- 模拟器运行：`flutter run -d ios`
- CI/无签名构建：`flutter build ios --no-codesign`

**App Transport Security（ATS）**：`[ios/Runner/Info.plist](ios/Runner/Info.plist)` 当前允许任意 HTTP（便于开发期访问 `http://` 的大模型网关）。如需上架 App Store，建议在明确域名后收紧 ATS（例如按域名做例外）。

### Android

```bash
flutter build apk
# 或
flutter build appbundle
```

签名配置请按 Flutter Android 部署文档配置，并在 `android/app/build.gradle.kts` 中补齐 release signing。

---

## 持续集成

GitHub Actions 工作流 `[.github/workflows/ios.yml](.github/workflows/ios.yml)` 会在 push / PR（`main` 与 `master`）时运行：

- `flutter pub get`
- `flutter test`
- `flutter build ios --no-codesign`（`macos-latest`）

如需 Android 侧的构建与测试，可在此基础上扩展 workflow。

---

## 参与贡献

欢迎贡献：

1. 先开一个 **issue** 描述 bug 或需求（或在已有 issue 下讨论）
2. fork 仓库并从默认分支创建 **feature branch**
3. 保持改动聚焦，并遵循项目现有 Dart 风格与 `[analysis_options.yaml](analysis_options.yaml)`
4. 本地运行 `flutter test`，确保必要构建能通过
5. 提交 **pull request**，UI 相关改动建议附截图

---

## 安全

- **不要**提交 GitHub Token、大模型 API key、或私有仓库 URL 等敏感信息
- 一旦泄露请立即轮换/作废相关凭据
- 如需负责任披露安全问题，请私下联系维护者（项目公开联系方式后可在此补充）

---

## 许可证

当前仓库根目录未包含 `LICENSE` 文件。如果你希望对外分发或接受外部贡献，建议补充明确的许可证（例如 MIT / Apache-2.0），并同步更新本节内容。

---

## 致谢

- [Flutter](https://flutter.dev) 与 Dart 团队
- [Forui](https://forui.dev/)
- [GitHub REST API](https://docs.github.com/en/rest)

