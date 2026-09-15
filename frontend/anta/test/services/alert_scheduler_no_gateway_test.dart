import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:anta/services/alert_scheduler.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/event_skip_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';

/// `CalendarBloc`'s default reconciler runs **unawaited** from a handler, and
/// most widget suites build that bloc under a `path_provider` stub without
/// registering an [AlertGateway]. If resolving the scheduler reached
/// `AppDatabase.getInstance()` before the GetIt lookup failed, it would claim
/// the app-wide database singleton — and create a real file in the test's temp
/// directory — out from under the in-memory database the test is using, at an
/// arbitrary moment in the middle of it.
///
/// So the gateway check has to come first, and *nothing* may run before it.
/// The `path_provider` counter is the proof: a database cannot be opened
/// without it.
///
/// This file has its own binding deliberately — every other suite that stubs
/// `path_provider` has already opened the singleton by the time its first test
/// runs, which would make the counter meaningless.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  var pathProviderCalls = 0;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_alert_no_gateway');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            pathProviderCalls++;
            return tempDir.path;
          },
        );
  });

  setUp(() {
    DatabaseLifecycle.notifyDatabaseSwitching();
    AlertScheduler.reset();
    CalendarEventService.reset();
    EventAlertService.reset();
    EventSkipService.reset();
    PublicHolidayService.reset();
    SettingsService.reset();
    if (GetIt.I.isRegistered<AlertGateway>()) {
      GetIt.I.unregister<AlertGateway>();
    }
    pathProviderCalls = 0;
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('reconcileEventById opens nothing when no gateway is registered',
      () async {
    await AlertScheduler.reconcileEventById(
      'e1',
      AlertReconcileReason.eventChanged,
    );

    expect(
      pathProviderCalls,
      0,
      reason: 'a database cannot be opened without path_provider',
    );
  });

  test('getInstance refuses before touching a database', () async {
    await expectLater(AlertScheduler.getInstance(), throwsStateError);

    expect(pathProviderCalls, 0);
  });

  test('a failed resolve leaves no singleton behind to poison the next call',
      () async {
    await AlertScheduler.reconcileEventById(
      'e1',
      AlertReconcileReason.eventChanged,
    );
    await AlertScheduler.reconcileEventById(
      'e2',
      AlertReconcileReason.eventChanged,
    );

    expect(pathProviderCalls, 0);
  });

  // Last, because it genuinely opens the app-wide database: the control that
  // shows the guard is what stopped the three above, and not some other
  // accident of this file's setup.
  test('registering a gateway is what lets the pass through', () async {
    GetIt.I.registerSingleton<AlertGateway>(const NoOpAlertGateway());
    addTearDown(() async {
      await (await AppDatabase.getInstance()).close();
      GetIt.I.unregister<AlertGateway>();
    });

    await AlertScheduler.reconcileEventById(
      'e1',
      AlertReconcileReason.eventChanged,
    );

    expect(pathProviderCalls, greaterThan(0));
  });
}
