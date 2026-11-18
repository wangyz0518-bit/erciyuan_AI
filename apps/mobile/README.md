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
The visible home/chat page is still Mock and does not yet wire in the
SQLite repositories, real AI, accounts, attachments, audio or avatar SDK.
The persistence and memory APIs described below are available to later features.

Architecture: `lib/bootstrap.dart` owns object assembly, UI under
`features/characters/presentation/` observes
`features/characters/application/`; domain owns `PersonScope` and the
`CharacterCatalog` port, while `data/` supplies a deterministic Mock.
The mock owner ID is only a local fixture; **never treat it as real authentication**.
SQLite PersonDatabase now lives in `lib/features/timeline/data/person_database.dart`.
It stores character timelines and append-only raw events, including per-character
transactional sequences, migrations v1→v2→v3 and vendor-independent owner export.
`test/person_database_test.dart` runs native SQLite on Linux using an injected
FFI database factory. The visible starter page remains clearly marked Mock;
the formal UI/repository wiring belongs to #37. No account login is present.
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
