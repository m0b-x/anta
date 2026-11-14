import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/database_replacing.dart';
import 'package:anta/services/fresh_preferences.dart';
import 'package:anta/services/shared_refresh/shared_refresh_memory.dart';

/// A store whose read answers with what stood when it was asked, a moment
/// later — a platform round trip.
class _SlowReads extends InMemorySharedPreferencesStore {
  _SlowReads() : super.empty();

  Duration delay = Duration.zero;

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    final snapshot = Map<String, Object>.of(
      await super.getAllWithParameters(parameters),
    );
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return snapshot;
  }
}

/// Keys another isolate writes are read from the platform's store itself,
/// never by replacing this isolate's copy of the preferences
/// (`docs/cloud-shared-freshness.md`; the closing review, K3): a re-read
/// that replaced the copy dropped whatever the app wrote while it was out.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SlowReads store;

  setUp(() {
    SharedPreferences.resetStatic();
    store = _SlowReads();
    SharedPreferencesStorePlatform.instance = store;
    DatabaseManager.resetForTesting();
  });

  Future<Set<String>> stored() async => (await store.getAll()).keys.toSet();

  test('the marker of a replacement that began while a pass read the '
      'plan\'s memory is gone from the store after its scope (probe '
      'R8-B1): the re-read dropped it from the app\'s copy, and the clear '
      'that asked the copy skipped the removal', () async {
    await SharedPreferences.getInstance();
    store.delay = const Duration(milliseconds: 60);
    final pass = const PreferencesSharedRefreshMemory().standing();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await DatabaseReplacing.run(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await pass;
    store.delay = Duration.zero;

    expect(
      await stored(),
      isNot(contains('flutter.${SettingsKeys.databaseReplacing}')),
    );
    expect(await DatabaseReplacing.standingIfKnown(), isFalse);
  });

  test('a write the app issues while such a read is out survives in the '
      'app\'s own copy (probe R8-B2): the active database\'s name', () async {
    final manager = await DatabaseManager.getInstance();
    await manager.setActiveDatabaseName('first');
    store.delay = const Duration(milliseconds: 60);
    final pass = const PreferencesSharedRefreshMemory().standing();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await manager.setActiveDatabaseName('second');
    await pass;
    store.delay = Duration.zero;

    expect(manager.getActiveDatabaseName(), 'second');
    expect(await DatabaseManager.peekActiveDatabaseName(), 'second');
  });

  test(
    'a fresh read answers what the store holds now, typed as the '
    'preferences type it, and leaves this isolate\'s copy as it was',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mine', 'kept');
      // Another isolate's writes.
      await store.setValue('Int', 'flutter.count', 2);
      await store.setValue('String', 'flutter.name', 'main');
      await store.setValue('StringList', 'flutter.names', <String>['a', 'b']);
      await store.remove('flutter.mine');

      final fresh = await FreshPreferences.read();

      expect(fresh.getInt('count'), 2);
      expect(fresh.getString('name'), 'main');
      expect(fresh.getStringList('names'), ['a', 'b']);
      expect(fresh.containsKey('mine'), isFalse);
      expect(fresh.getInt('name'), isNull, reason: 'another type is no value');
      expect(prefs.getString('mine'), 'kept');
      expect(prefs.containsKey('count'), isFalse);
    },
  );
}
