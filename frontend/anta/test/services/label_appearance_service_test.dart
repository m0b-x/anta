import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/label_appearance.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/label_style.dart';
import 'package:anta/services/label_appearance_service.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

/// Runs the real settings row and the real facade against
/// `NativeDatabase.memory()`.
///
/// The service exists for one reason — rows read the style synchronously —
/// so what earns a test is that the published value and the stored one can
/// never disagree: the read seeds the facade before the first frame, a write
/// persists *and* publishes, and a database switch re-reads rather than
/// carrying the previous database's preference into the next one.
void main() {
  late AppDatabase db;
  late SettingsService settings;

  setUp(() async {
    LabelAppearanceService.reset();
    SettingsService.reset();
    LabelAppearance.style.value = LabelStyle.dot;
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
  });

  tearDown(() async {
    LabelAppearanceService.reset();
    SettingsService.reset();
    LabelAppearance.style.value = LabelStyle.dot;
    // Every DB-backed singleton this file touched registered a reset handler;
    // firing them before the handle closes is the lifecycle contract, and
    // without it a later suite inherits a service bound to a dead database.
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  test('a fresh install publishes the dot', () async {
    final service = await LabelAppearanceService.getInstance();

    expect(service.style, LabelStyle.dot);
    expect(LabelAppearance.style.value, LabelStyle.dot);
    expect(SettingsKeys.defaultLabelStyle, LabelStyle.dot.name);
  });

  test('getInstance publishes the persisted style', () async {
    await settings.setLabelStyle(LabelStyle.stripe);

    final service = await LabelAppearanceService.getInstance();

    expect(service.style, LabelStyle.stripe);
    expect(LabelAppearance.style.value, LabelStyle.stripe);
  });

  test('an unknown stored name reads as the dot rather than throwing', () async {
    await db.userSettingsDao.setValue(SettingsKeys.labelStyle, 'hologram');

    final service = await LabelAppearanceService.getInstance();

    expect(service.style, LabelStyle.dot);
    expect(LabelAppearance.style.value, LabelStyle.dot);
  });

  test('setStyle persists and publishes, in that order', () async {
    final service = await LabelAppearanceService.getInstance();
    final published = <LabelStyle>[];
    void listener() => published.add(LabelAppearance.style.value);
    LabelAppearance.style.addListener(listener);
    addTearDown(() => LabelAppearance.style.removeListener(listener));

    await service.setStyle(LabelStyle.stripe);

    expect(await settings.getLabelStyle(), LabelStyle.stripe);
    expect(service.style, LabelStyle.stripe);
    expect(published, [LabelStyle.stripe]);
  });

  /// The order claim, proved rather than asserted after the fact: the
  /// notifier fires synchronously, so a listener that looks at the statements
  /// the database has already received is reading the state of the world at
  /// the instant of publication. A row repainting off a value the store then
  /// failed to take would be lying about the next launch.
  test('the store has the row before any listener sees the new value',
      () async {
    LabelAppearanceService.reset();
    SettingsService.reset();
    final counter = StatementCounter();
    final counted = await openTestDatabase(interceptor: counter);
    addTearDown(counted.close);
    SettingsService.forTesting(counted);
    final service = await LabelAppearanceService.getInstance();

    bool labelStyleWritten() => counter.captured.any(
      (statement) =>
          !statement.isSelect &&
          statement.args.contains(SettingsKeys.labelStyle),
    );

    counter.reset();
    bool? writtenAtPublish;
    void listener() => writtenAtPublish ??= labelStyleWritten();
    LabelAppearance.style.addListener(listener);
    addTearDown(() => LabelAppearance.style.removeListener(listener));

    await service.setStyle(LabelStyle.stripe);

    expect(writtenAtPublish, isTrue, reason: 'the write lands first');
    expect(
      await counted.userSettingsDao.getValue(SettingsKeys.labelStyle),
      LabelStyle.stripe.name,
    );
  });

  test('setting the style it already has still writes the row, and notifies '
      'nobody', () async {
    final service = await LabelAppearanceService.getInstance();
    await db.userSettingsDao.deleteValue(SettingsKeys.labelStyle);
    expect(await db.userSettingsDao.getValue(SettingsKeys.labelStyle), isNull);
    var notifications = 0;
    void listener() => notifications++;
    LabelAppearance.style.addListener(listener);
    addTearDown(() => LabelAppearance.style.removeListener(listener));

    await service.setStyle(LabelStyle.dot);

    expect(
      await db.userSettingsDao.getValue(SettingsKeys.labelStyle),
      LabelStyle.dot.name,
      reason:
          '"Reset to defaults" relies on the row existing, so a backup '
          'carries the default explicitly rather than by omission',
    );
    expect(
      notifications,
      0,
      reason: 'the notifier only fires when the value actually moves',
    );
  });

  test('a single instance is shared by concurrent first callers', () async {
    final results = await Future.wait([
      LabelAppearanceService.getInstance(),
      LabelAppearanceService.getInstance(),
    ]);

    expect(identical(results.first, results.last), isTrue);
  });

  test('reset then getInstance re-reads the store', () async {
    final service = await LabelAppearanceService.getInstance();
    await service.setStyle(LabelStyle.stripe);

    LabelAppearanceService.reset();
    // The facade deliberately keeps its value across a reset — blanking it
    // would flash every labelled row back to the dot between two databases.
    expect(LabelAppearance.style.value, LabelStyle.stripe);

    await settings.setLabelStyle(LabelStyle.dot);
    final reloaded = await LabelAppearanceService.getInstance();

    expect(identical(reloaded, service), isFalse);
    expect(reloaded.style, LabelStyle.dot);
    expect(LabelAppearance.style.value, LabelStyle.dot);
  });

  /// Deterministic because `_create` cannot get past its first `await` before
  /// the reset lands: the generation it captured is already stale by the time
  /// it looks, so it discards itself and hands its caller the service the
  /// *next* creation installs, rather than one bound to the closed database.
  test('a reset while the first getInstance is in flight discards that one',
      () async {
    await settings.setLabelStyle(LabelStyle.stripe);

    final inFlight = LabelAppearanceService.getInstance();
    LabelAppearanceService.reset();
    final service = await inFlight;

    expect(
      identical(await LabelAppearanceService.getInstance(), service),
      isTrue,
      reason: 'the discarded creation must not be handed out to anyone',
    );
    expect(service.style, LabelStyle.stripe);
    expect(LabelAppearance.style.value, LabelStyle.stripe);
  });
}
