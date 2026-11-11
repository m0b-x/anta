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
  late int signOuts;
  late bool signOutThrows;

  QaBootstrap build({
    String databaseName = 'qa',
    bool skipOnboarding = true,
    bool signOutOnReset = false,
    bool enabled = true,
  }) {
    return QaBootstrap(
      documentsPath: documents,
      databaseName: databaseName,
      skipOnboarding: skipOnboarding,
      signOutOnReset: signOutOnReset,
      enabled: enabled,
      signOut: () async {
        signOuts++;
        if (signOutThrows) throw StateError('auth down');
      },
      clearPreferences: () async => prefsCleared++,
      importSeed: (json) async {
        importedSeeds.add(json);
        if (seedThrows) throw StateError('bad fixture');
        return (true, 'ok');
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
    QaBootstrap.log.clear();
    QaBootstrap.entries.clear();
    tempDir = await Directory.systemTemp.createTemp('anta_qa_bootstrap');
    documents = tempDir.path;
    prefsCleared = 0;
    importedSeeds = [];
    seedThrows = false;
    onboardingCompleted = false;
    onboardingMarked = 0;
    signOuts = 0;
    signOutThrows = false;
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

  group('reset sign-out', () {
    test('a reset launch on the emulator build signs out', () async {
      await marker('qa_reset').writeAsString('');
      final bootstrap = build(signOutOnReset: true);
      await bootstrap.applyResetMarker();

      expect(await bootstrap.applyResetSignOut(), isTrue);
      expect(signOuts, 1);
      expect(QaBootstrap.entries.last.kind, 'signout');
      expect(QaBootstrap.entries.last.ok, isTrue);
    });

    test('a launch without the reset keeps the session', () async {
      final bootstrap = build(signOutOnReset: true);
      await bootstrap.applyResetMarker();

      expect(await bootstrap.applyResetSignOut(), isFalse);
      expect(signOuts, 0);
    });

    test('a reset refused for the owner database keeps the session', () async {
      await marker('qa_reset').writeAsString('');
      final bootstrap = build(databaseName: 'gym_notes', signOutOnReset: true);
      await bootstrap.applyResetMarker();

      expect(await bootstrap.applyResetSignOut(), isFalse);
      expect(signOuts, 0);
    });

    test('a build without the emulator never signs out', () async {
      await marker('qa_reset').writeAsString('');
      final bootstrap = build();
      await bootstrap.applyResetMarker();

      expect(await bootstrap.applyResetSignOut(), isFalse);
      expect(signOuts, 0);
    });

    test('a sign-out that throws is a logged failure, not a crash', () async {
      signOutThrows = true;
      await marker('qa_reset').writeAsString('');
      final bootstrap = build(signOutOnReset: true);
      await bootstrap.applyResetMarker();

      expect(await bootstrap.applyResetSignOut(), isFalse);
      expect(signOuts, 1);
      expect(QaBootstrap.entries.last.kind, 'signout');
      expect(QaBootstrap.entries.last.ok, isFalse);
    });
  });

  group('reset quiet', () {
    late int quiets;

    QaBootstrap quieting({bool throws = false, bool enabled = true}) {
      quiets = 0;
      final base = build(enabled: enabled);
      return QaBootstrap(
        documentsPath: base.documentsPath,
        clearPreferences: base.clearPreferences,
        importSeed: base.importSeed,
        isOnboardingCompleted: base.isOnboardingCompleted,
        markOnboardingCompleted: base.markOnboardingCompleted,
        signOut: base.signOut,
        signOutOnReset: false,
        enabled: enabled,
        quietAlerts: () async {
          quiets++;
          if (throws) throw StateError('no binding');
          return 'stopped 1 ring(s), cancelled 0 alarm(s), took down 0 '
              'notification(s)';
        },
      );
    }

    test('a reset launch ends what the alert tier kept and says so', () async {
      await marker('qa_reset').writeAsString('');
      final bootstrap = quieting();
      await bootstrap.applyResetMarker();

      expect(await bootstrap.applyResetQuiet(), isTrue);
      expect(quiets, 1);
      expect(QaBootstrap.entries.last.kind, 'quiet');
      expect(QaBootstrap.log.last, startsWith('quiet: stopped 1 ring(s)'));
    });

    test('a launch without the reset leaves a ring alone', () async {
      final bootstrap = quieting();
      await bootstrap.applyResetMarker();

      expect(await bootstrap.applyResetQuiet(), isFalse);
      expect(quiets, 0);
    });

    test('a quiet that throws is a logged failure, not a crash', () async {
      await marker('qa_reset').writeAsString('');
      final bootstrap = quieting(throws: true);
      await bootstrap.applyResetMarker();

      expect(await bootstrap.applyResetQuiet(), isFalse);
      expect(QaBootstrap.entries.last.kind, 'quiet');
      expect(QaBootstrap.entries.last.ok, isFalse);
    });

    test('a disabled build quiets nothing', () async {
      await marker('qa_reset').writeAsString('');
      final bootstrap = quieting(enabled: false);
      await bootstrap.applyResetMarker();

      expect(await bootstrap.applyResetQuiet(), isFalse);
      expect(quiets, 0);
    });
  });

  group('disabled', () {
    test('every hook is a no-op and every marker survives', () async {
      await seedDatabaseFiles();
      await marker('qa_reset').writeAsString('');
      await marker('qa_seed.json').writeAsString('{}');

      final bootstrap = build(enabled: false, signOutOnReset: true);
      expect(await bootstrap.applyResetMarker(), isFalse);
      expect(await bootstrap.applyResetSignOut(), isFalse);
      await bootstrap.applySeedMarker();
      expect(await bootstrap.applyOnboardingSkip(), isFalse);

      expect(prefsCleared, 0);
      expect(signOuts, 0);
      expect(importedSeeds, isEmpty);
      expect(onboardingMarked, 0);
      expect(await database('qa').exists(), isTrue);
      expect(await marker('qa_reset').exists(), isTrue);
      expect(await marker('qa_seed.json').exists(), isTrue);
    });
  });

  group('log', () {
    test(
      'every [qa] line is kept in order for the agent to hand back',
      () async {
        await marker('qa_reset').writeAsString('');
        await marker('qa_seed.json').writeAsString('{"version": 7}');
        final bootstrap = build();
        await bootstrap.applyResetMarker();
        await bootstrap.applySeedMarker();
        await bootstrap.applyOnboardingSkip();
        expect(QaBootstrap.log, [
          'reset: cleared preferences and qa.db',
          'seed: ok',
          'onboarding marked completed',
        ]);
        expect(QaBootstrap.entries.map((e) => (e.kind, e.ok)), [
          ('reset', true),
          ('seed', true),
          ('onboarding', true),
        ]);
      },
    );

    test('a seed that throws is a typed failure, not a wording', () async {
      seedThrows = true;
      await marker('qa_seed.json').writeAsString('{}');
      await build().applySeedMarker();
      final entry = QaBootstrap.entries.single;
      expect(entry.kind, 'seed');
      expect(entry.ok, isFalse);
      expect(entry.toJson(), {
        'kind': 'seed',
        'ok': false,
        'message': entry.message,
      });
    });

    test('a refused reset is logged too', () async {
      await marker('qa_reset').writeAsString('');
      await build(databaseName: 'gym_notes').applyResetMarker();
      expect(QaBootstrap.log.single, startsWith('reset refused'));
    });
  });
}
