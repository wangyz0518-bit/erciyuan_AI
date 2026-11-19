# erciyuan mobile · official app

The official app uses one persistent timeline per character. For role-specific
speech, hold-to-talk and continuous calls, see the [person gateway guide](../../services/person_gateway/README.md).
The earlier [PoC](../mobile_poc/) is a separate project. Use Flutter **3.50.0**,
Java **17**, Android SDK/Gradle compatible with the checked-in native template.

```bash
cd apps/mobile
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
flutter run
```

The starter characters 小星 and 小月 have separate SQLite timelines.
Continue opens the selected character's saved conversation. The app starts
in offline demo mode. A configured local gateway enables additional chat and
voice modes. Imports and spoken replies are scoped to the selected character.

## 动态形象与本机 Android 人物包

普通 Android 和 iOS 构建使用 Flutter 内置形象。倾听、等待回复和朗读有不同的表现，
角色语音播放时根据 PCM 音量估计开口幅度。GitHub 构建只发布内置形象版本。

开发机可以为 Android 启用已有的 Cubism Native 5-r.5 SDK。在本机 PowerShell
中指向已解压的 SDK 根目录，然后从 `apps/mobile` 启动应用。

```powershell
$env:ERCIYUAN_CUBISM_SDK = 'D:\local-sdk\CubismSdkForNative-5-r.5'
flutter run -d emulator-5554
```

进入人物的聊天页，点击右上角人物形象菜单，选择 v0.1 人物 ZIP。
导入经结构和 SDK 校验后生效，绑定随本机用户和人物保存。菜单中的“恢复内置形象”
可以解除当前绑定。人物包和 SDK 由开发者本机提供，许可进度见 [#80](https://github.com/wangyz0518-bit/erciyuan_AI/issues/80)。
在普通 PowerShell 会话中构建默认 APK，运行以下命令检查公开包内容。

```sh
flutter build apk --debug
python tool/check_public_avatar_apk.py build/app/outputs/flutter-apk/app-debug.apk
```

Android 形象测试在 `integration_test/character_avatar_test.dart`。默认验证内置形象。
私有 SDK 构建可通过 `--dart-define=AVATAR_TEST_ZIP=<设备端样包路径>` 验证导入、动作、
人物切换和重新打开。可选的 `AVATAR_TEST_UPGRADE` 和 `AVATAR_TEST_INVALID`
分别指定同一人物包的新版和无效样包，用于检查升级与失败回退。

## Storage

Architecture: `lib/bootstrap.dart` owns object assembly, UI under
`features/characters/presentation/` observes
`features/characters/application/`; domain owns `PersonScope` and the
`CharacterCatalog` port, while `data/` supplies a deterministic Mock.
The mock owner ID is only a local fixture; **never treat it as real authentication**.
SQLite PersonDatabase now lives in `lib/features/timeline/data/person_database.dart`.
It stores character timelines and append-only raw events, including per-character
transactional sequences, migrations v1→v2→v3 and vendor-independent owner export.
`test/person_database_test.dart` runs native SQLite on Linux using an injected
FFI database factory. The local starter owner has no account login.
Offline memory (#47) lives in lib/features/memory/. It adds source-linked
archive summaries, searchable terms, atomic archive cursors, user-confirmed
identity versions, context assembly and transaction-consistent three-layer JSON
export. Pass automaticSummarizer: const DeterministicSummarizer() when opening
PersonDatabase to enable event-triggered offline archiving, or call memory.archiveReady
for retry. The deterministic baseline is NOT a real model summary; it does not
prove memory retrieval quality, provider prompt caching or token costs.
See test/person_memory_test.dart and plan/issue-47-memory-implementation-20261118.md.
No memory-management UI is wired yet; the live integration belongs to #37/#39.

Android Debug build is checked by `.github/workflows/flutter-mobile.yml`.
The iOS native template is present but no iOS Simulator or physical device
verification is claimed in #35. #40 tracks macOS/Xcode verification.
This foundation does not run the deferred PoC emulator CI task #31.
