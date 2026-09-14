import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:anta/core/qa/qa_bootstrap.dart';

/// The QA build is driven entirely by files dropped next to the databases, so
/// these are the seams that decide whether an automation run starts from a
/// known state — and whether it can reach the owner's data by accident.
void main() {
  late Directory tempDir;
  late String documents;

  late int prefsCleared;
  late List<String> importedSeeds;
  late bool seedThrows;
  late bool onboardingCompleted;
  late int onboardingMarked;

  QaBootstrap build({
    String databaseName = 'qa',
    bool skipOnboarding = true,
    bool enabled = true,
  }) {
    return QaBootstrap(
      documentsPath: documents,
      databaseName: databaseName,
      skipOnboarding: skipOnboarding,
      enabled: enabled,
      clearPreferences: () async => prefsCleared++,
      importSeed: (json) async {
        importedSeeds.add(json);
        if (seedThrows) throw StateError('bad fixture');
        return 'ok';
      },
      isOnboardingCompleted: () async => onboardingCompleted,
      markOnboardingCompleted: () async {
        onboardingMarked++;
        onboardingCompleted = true;
      },
    );
  }

  File marker(String name) => File(p.join(documents, name));
  File database(String name) =>
      File(p.join(documents, 'gym_notes', '$name.db'));

  Future<void> seedDatabaseFiles() async {
    final dir = Directory(p.join(documents, 'gym_notes'));
    await dir.create(recursive: true);
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      await File('${database('qa').path}$suffix').writeAsString('qa');
    }
    await database('gym_notes').writeAsString('owner');
    await File(p.join(dir.path, 'device_id')).writeAsString('device-1');
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_qa_bootstrap');
    documents = tempDir.path;
    prefsCleared = 0;
    importedSeeds = [];
    seedThrows = false;
    onboardingCompleted = false;
    onboardingMarked = 0;
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('reset marker', () {
    test('clears preferences and the QA database, nothing else', () async {
      await seedDatabaseFiles();
      await marker('qa_reset').writeAsString('');

      expect(await build().applyResetMarker(), isTrue);

      expect(prefsCleared, 1);
      for (final suffix in const ['', '-wal', '-shm', '-journal']) {
        expect(
          await File('${database('qa').path}$suffix').exists(),
          isFalse,
          reason: 'qa.db$suffix should be gone',
        );
      }
      expect(
        await database('gym_notes').exists(),
        isTrue,
        reason: "the owner's database is never touched",
      );
      expect(
        await File(p.join(documents, 'gym_notes', 'device_id')).exists(),
        isTrue,
        reason: 'the device id is identity, not data',
      );
      expect(
        await marker('qa_reset').exists(),
        isFalse,
        reason: 'a marker left behind would wipe every later launch',
      );
    });

    test('does nothing without the marker', () async {
      await seedDatabaseFiles();

      expect(await build().applyResetMarker(), isFalse);
      expect(prefsCleared, 0);
      expect(await database('qa').exists(), isTrue);
    });

    test('refuses to delete the owner database when misconfigured', () async {
      await seedDatabaseFiles();
      await marker('qa_reset').writeAsString('');

      expect(
        await build(databaseName: 'gym_notes').applyResetMarker(),
        isFalse,
      );
      expect(prefsCleared, 0);
      expect(await database('gym_notes').exists(), isTrue);
      expect(await marker('qa_reset').exists(), isFalse);
    });

    test('tolerates a database that was never created', () async {
      await marker('qa_reset').writeAsString('');

      expect(await build().applyResetMarker(), isTrue);
      expect(prefsCleared, 1);
    });
  });

  group('seed marker', () {
    test('hands the importer the file contents and removes it', () async {
      await marker('qa_seed.json').writeAsString('{"folders":[]}');

      await build().applySeedMarker();

      expect(importedSeeds, ['{"folders":[]}']);
      expect(await marker('qa_seed.json').exists(), isFalse);
    });

    test('removes the marker even when the import throws', () async {
      seedThrows = true;
      await marker('qa_seed.json').writeAsString('{');

      await build().applySeedMarker();

      expect(importedSeeds, hasLength(1));
      expect(
        await marker('qa_seed.json').exists(),
        isFalse,
        reason: 'a bad fixture costs one launch, not every launch after it',
      );
    });

    test('does nothing without the marker', () async {
      await build().applySeedMarker();
      expect(importedSeeds, isEmpty);
    });
  });

  group('onboarding skip', () {
    test('marks onboarding completed when it is not', () async {
      expect(await build().applyOnboardingSkip(), isTrue);
      expect(onboardingMarked, 1);
    });

    test('leaves an already completed flag alone', () async {
      onboardingCompleted = true;

      expect(await build().applyOnboardingSkip(), isFalse);
      expect(onboardingMarked, 0);
    });

    test('respects ANTA_QA_SKIP_ONBOARDING=false', () async {
      expect(await build(skipOnboarding: false).applyOnboardingSkip(), isFalse);
      expect(onboardingMarked, 0);
    });
  });

  group('disabled', () {
    test('every hook is a no-op and every marker survives', () async {
      await seedDatabaseFiles();
      await marker('qa_reset').writeAsString('');
      await marker('qa_seed.json').writeAsString('{}');

      final bootstrap = build(enabled: false);
      expect(await bootstrap.applyResetMarker(), isFalse);
      await bootstrap.applySeedMarker();
      expect(await bootstrap.applyOnboardingSkip(), isFalse);

      expect(prefsCleared, 0);
      expect(importedSeeds, isEmpty);
      expect(onboardingMarked, 0);
      expect(await database('qa').exists(), isTrue);
      expect(await marker('qa_reset').exists(), isTrue);
      expect(await marker('qa_seed.json').exists(), isTrue);
    });
  });
}
