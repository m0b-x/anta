import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/database_replacing.dart';

import '../support/scripted_prefs_store.dart';

/// `DatabaseReplacing` — the marker an isolate that is not the app's reads
/// before it opens a database (`docs/cloud-shared-freshness.md` §5), and the
/// read-only look at the active name the same isolate takes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DatabaseManager.resetForTesting();
  });

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  test('stands for as long as the body runs, and is gone after it — '
      'however it ends', () async {
    expect(await DatabaseReplacing.standing(), isFalse);

    late bool during;
    await DatabaseReplacing.run(() async {
      during = await DatabaseReplacing.standing();
    });
    expect(during, isTrue);
    expect(await DatabaseReplacing.standing(), isFalse);

    await expectLater(
      DatabaseReplacing.run<void>(() async => throw StateError('disk full')),
      throwsStateError,
    );
    expect(await DatabaseReplacing.standing(), isFalse);
  });

  test('nested scopes: the marker goes with the outermost', () async {
    late bool afterInner;
    await DatabaseReplacing.run(() async {
      await DatabaseReplacing.run(() async {});
      afterInner = await DatabaseReplacing.standing();
    });

    expect(afterInner, isTrue);
    expect(await DatabaseReplacing.standing(), isFalse);
  });

  test('a download between its switch and its bind is a replacement too: '
      'one question reads both', () async {
    await (await prefs()).setString(
      SettingsKeys.syncDownloadInFlight,
      '{"from":"a","to":"b"}',
    );

    expect(await DatabaseReplacing.standing(), isTrue);
  });

  test('asking never clears: a marker a dead process left stands until '
      'the launch takes it off', () async {
    await (await prefs()).setString(SettingsKeys.databaseReplacing, '1');

    expect(await DatabaseReplacing.standing(), isTrue);
    expect(await DatabaseReplacing.standing(), isTrue);
    expect((await prefs()).getString(SettingsKeys.databaseReplacing), '1');

    await DatabaseReplacing.clearLeftBehind();
    expect(await DatabaseReplacing.standing(), isFalse);
  });

  test(
    'the launch\'s clear leaves a replacement of this isolate standing',
    () async {
      await DatabaseReplacing.run(() async {
        await DatabaseReplacing.clearLeftBehind();
        expect(await DatabaseReplacing.standing(), isTrue);
      });
    },
  );

  group('asked from another isolate, whose preferences are a copy', () {
    Future<void> writeBehind(String key, String value) =>
        SharedPreferencesStorePlatform.instance.setValue(
          'String',
          'flutter.$key',
          value,
        );

    test('the marker is re-read each time it is asked (review H11): one '
        'raised or taken off by the app after this isolate loaded its copy '
        'is the answer', () async {
      expect(await DatabaseReplacing.standing(), isFalse);

      await writeBehind(SettingsKeys.databaseReplacing, '1');
      expect(await DatabaseReplacing.standing(), isTrue);

      await SharedPreferencesStorePlatform.instance.remove(
        'flutter.${SettingsKeys.databaseReplacing}',
      );
      expect(await DatabaseReplacing.standingIfKnown(), isFalse);
    });

    test('the active name is re-read too (review H9): the app switched '
        'databases after this isolate loaded its copy', () async {
      SharedPreferences.setMockInitialValues({'active_database': 'first'});
      expect(await DatabaseManager.peekActiveDatabaseName(), 'first');

      await writeBehind('active_database', 'second');

      expect(await DatabaseManager.peekActiveDatabaseName(), 'second');
    });

    test('a store that cannot be read is told apart from a marker that '
        'stands (review H6b): unknown for the check, which is asked again — '
        'and still no licence to open for whoever asks yes or no', () async {
      final store = ScriptedPrefsStore.install();
      await prefs();
      store.onRead = (_) => throw StateError('store');

      expect(await DatabaseReplacing.standingIfKnown(), isNull);
      expect(await DatabaseReplacing.standing(), isTrue);

      store.onRead = null;
      expect(await DatabaseReplacing.standingIfKnown(), isFalse);
    });
  });

  group('a marker the store refused to remove (review H6a)', () {
    Future<bool> held(ScriptedPrefsStore store) async => (await store.getAll())
        .containsKey('flutter.${SettingsKeys.databaseReplacing}');

    test('is taken off by the next resume, though this isolate\'s own copy '
        'says it is gone', () async {
      final store = ScriptedPrefsStore.install();
      store.refuseRemove = (key) => key == SettingsKeys.databaseReplacing;

      await DatabaseReplacing.run(() async {});
      expect(await held(store), isTrue, reason: 'the store kept it');
      expect(
        (await prefs()).containsKey(SettingsKeys.databaseReplacing),
        isFalse,
        reason: 'and the copy dropped it: asked, it would skip the removal',
      );

      // A resume the store still refuses leaves the removal owed.
      await DatabaseReplacing.clearLeftBehind();
      expect(await held(store), isTrue);

      store.refuseRemove = null;
      await DatabaseReplacing.clearLeftBehind();
      expect(await held(store), isFalse);
    });

    test('a removal that threw is owed the same way', () async {
      final store = ScriptedPrefsStore.install();

      await DatabaseReplacing.run(() async {
        store.failWrite = (key) => key == SettingsKeys.databaseReplacing;
      });
      expect(await held(store), isTrue);

      store.failWrite = null;
      await DatabaseReplacing.clearLeftBehind();
      expect(await held(store), isFalse);
    });

    test('a resume during an import takes nothing off: the marker stands '
        'until the import\'s own end', () async {
      final store = ScriptedPrefsStore.install();

      await DatabaseReplacing.run(() async {
        await DatabaseReplacing.clearLeftBehind();
        expect(await held(store), isTrue);
      });
      expect(await held(store), isFalse);
    });
  });

  group('the active name, read only (review item 5)', () {
    test('peeking answers the stored name and writes nothing — the '
        'interrupted download\'s marker and the active name stay as they '
        'were, where the manager\'s own start would repair both', () async {
      SharedPreferences.setMockInitialValues({
        'active_database': 'downloaded',
        SettingsKeys.syncDownloadInFlight: '{"from":"old","to":"downloaded"}',
      });

      expect(await DatabaseManager.peekActiveDatabaseName(), 'downloaded');

      final stored = await prefs();
      expect(stored.getString('active_database'), 'downloaded');
      expect(
        stored.getString(SettingsKeys.syncDownloadInFlight),
        '{"from":"old","to":"downloaded"}',
      );
    });

    test('a manager built with the recovery off — in the check\'s own '
        'isolate — reads the same name and repairs nothing; built as the '
        'launch builds it, the marker is taken off', () async {
      const marker = '{"from":"old","to":"downloaded"}';
      SharedPreferences.setMockInitialValues({
        'active_database': 'downloaded',
        SettingsKeys.syncDownloadInFlight: marker,
      });
      DatabaseManager.recoversAtStart = false;
      addTearDown(() => DatabaseManager.recoversAtStart = true);

      final away = await DatabaseManager.getInstance();
      expect(away.getActiveDatabaseName(), 'downloaded');
      expect(
        (await prefs()).getString(SettingsKeys.syncDownloadInFlight),
        marker,
      );

      DatabaseManager.recoversAtStart = true;
      DatabaseManager.resetForTesting();
      await DatabaseManager.getInstance();
      expect(
        (await prefs()).getString(SettingsKeys.syncDownloadInFlight),
        isNull,
      );
    });

    test('with none stored it is the build\'s default', () async {
      expect(
        await DatabaseManager.peekActiveDatabaseName(),
        DatabaseManager.defaultDatabaseName(qaEnabled: false),
      );
    });
  });
}
