import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/sync/app_sync_apply_hooks.dart';
import 'package:anta/services/sync/sync_apply_hooks.dart';
import 'package:anta/services/sync/sync_table_binding.dart';

/// The app's calendar reload after a pull, through the real services over a
/// throwaway database: the event store is re-read only where a live service
/// holds it (scalability record §5.6, S13). Opening the service there loaded
/// the whole store for a calendar nobody had opened, and the bloc that later
/// opened it read the store again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late List<String> calls;
  late AppSyncApplyHooks hooks;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_hooks_calendar');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    calls = [];
    hooks = AppSyncApplyHooks(
      reconcileAlerts: () async => calls.add('reconcile'),
      strings: () async => lookupAppLocalizations(const Locale('en')),
      now: () => DateTime(2026, 11, 7, 9),
    );
  });

  tearDown(CalendarEventService.reset);

  test('a pull with no calendar open leaves the event store unread, and '
      'still signals', () async {
    CalendarEventService.reset();
    var signalled = 0;
    final subscription = CalendarEventService.externalChanges.listen(
      (_) => signalled++,
    );
    addTearDown(subscription.cancel);

    await hooks.afterRun({SyncInvalidation.calendar});
    await pumpEventQueue();

    expect(CalendarEventService.isLive, isFalse);
    expect(signalled, 1);
    expect(calls, ['reconcile']);
  });

  test('a live service re-reads the rows the pull merged', () async {
    final service = await CalendarEventService.getInstance();
    await service.upsert(
      CalendarEvent(
        id: 'pulled',
        title: 'Before',
        categoryId: 'gym',
        startDate: DateTime.utc(2026, 11, 7),
      ),
    );
    final db = await AppDatabase.getInstance();
    await db.customStatement(
      "UPDATE calendar_events SET title = 'After' WHERE id = 'pulled'",
    );
    expect(service.events.single.title, 'Before');

    await hooks.afterRun({SyncInvalidation.calendar});

    expect(service.events.single.title, 'After');
  });

  test('marks the shared reader cleared reach the event cache, though the '
      'run\'s one page of events carried another row (review C-1)', () async {
    final service = await CalendarEventService.getInstance();
    await service.upsert(
      CalendarEvent(
        id: 'mine',
        title: 'Dinner',
        categoryId: 'gym',
        startDate: DateTime.utc(2026, 11, 7),
      ),
    );
    bool mineShared() =>
        service.events.firstWhere((e) => e.id == 'mine').markedShared;
    await service.setShared('mine', 'pair-old');
    expect(mineShared(), isTrue);
    // The pair ended: the reader clears the marks under the cache, then
    // reads a partner's event in the same run.
    final db = await AppDatabase.getInstance();
    await db.folderDao.clearSharesExcept(null);
    await hooks.beforePage('calendar_events');
    await hooks.afterPage('calendar_events', const [
      SyncAppliedRow(
        rowKey: 'theirs',
        result: MergeResult.inserted,
        tombstone: false,
      ),
    ]);

    await hooks.afterRun({
      SyncInvalidation.calendar,
      SyncInvalidation.alerts,
      SyncInvalidation.shareMarks,
    });

    expect(mineShared(), isFalse);
  });
}
