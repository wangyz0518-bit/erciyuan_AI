# erciyuan mobile · official foundation (#35)

This is the **minimal official Flutter app**. The existing [PoC](../mobile_poc/)
remains unchanged. Use Flutter **3.50.0** (Dart bundled with Flutter 3.50),
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

The Home screen intentionally uses **Mock** characters and an **in-memory
character-scoped draft**. Its "continue" button always enters the same logical
timeline for the selected character. This is not the eventual persistent chat.
No AI provider, actual chat messages, account identity, memory engine,
attachments, audio, avatar SDK, login, or export are wired in this Issue.

Architecture: `lib/bootstrap.dart` owns object assembly, UI under
`features/characters/presentation/` observes
`features/characters/application/`; domain owns `PersonScope` and the
`CharacterCatalog` port, while `data/` supplies a deterministic Mock.
The mock owner ID is only a local fixture; **never treat it as real authentication**.
Persistent SQLite, migrations, RawEvent and export belong to #36;
memory archive, indexing and identity changes belong to #47.

Android Debug build is checked by `.github/workflows/flutter-mobile.yml`.
The iOS native template is present but no iOS Simulator or physical device
verification is claimed in #35. #40 tracks macOS/Xcode verification.
This foundation does not run the deferred PoC emulator CI task #31.
