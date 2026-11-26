import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../constants/calendar_icons.dart';
import '../constants/event_alerts.dart';
import '../constants/fasting_calendar.dart';
import '../constants/font_constants.dart';
import '../constants/settings_keys.dart';
import '../models/alert_sound.dart';
import '../models/editor_settings.dart';
import '../models/event_alert.dart';
import '../models/fasting_appearance.dart';
import '../models/fasting_schedule.dart';
import '../models/label_style.dart';
import '../models/nav_destination.dart';
import '../models/overview_list_options.dart';
import '../models/overview_period.dart';
import '../models/partner_folder_sort.dart';
import '../models/report_cards.dart';
import '../models/restore_location_mode.dart';
import '../models/share_settings.dart';
import 'sync/sync_cadence.dart';
import '../models/sync_binding.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/agenda_day_list_mode.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_grid_filters.dart';
import '../models/calendar_panel_mode.dart';
import '../models/color_picker_mode.dart';
import '../models/upcoming_agenda_filters.dart';
import '../models/utility_button_config.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/vocabulary_trigger.dart';

part 'settings_service/store.dart';
part 'settings_service/money_and_colours.dart';
part 'settings_service/general.dart';
part 'settings_service/editor.dart';
part 'settings_service/calendar_appearance.dart';
part 'settings_service/calendar_page.dart';
part 'settings_service/overview_and_report.dart';
part 'settings_service/fasting.dart';
part 'settings_service/alerts.dart';
part 'settings_service/sharing.dart';
part 'settings_service/sync.dart';
part 'settings_service/pairing_settings.dart';

/// Service for managing app settings using SQLite database
class SettingsService extends _SettingsStore
    with
        _MoneyAndColourSettings,
        _GeneralSettings,
        _EditorSettings,
        _CalendarAppearanceSettings,
        _CalendarPageSettings,
        _OverviewAndReportSettings,
        _FastingSettings,
        _AlertSettings,
        _ShareSettings,
        _SyncSettings {
  static SettingsService? _instance;

  /// How long [_scheduleWrite] waits for the next write to the same key.
  ///
  /// Only the font sizes are debounced, and they are driven by repeated +/-
  /// taps: 400 ms is long enough that a burst costs one write and short enough
  /// that a user who taps once and leaves the note has it persisted before the
  /// page's lifecycle flush would have to save it.
  static const Duration defaultWriteDebounce = Duration(milliseconds: 400);

  final Duration _writeDebounce;

  SettingsService._({Duration? writeDebounce})
    : _writeDebounce = writeDebounce ?? defaultWriteDebounce;

  /// The open in flight, shared by every caller that arrives before it
  /// finishes.
  static Future<SettingsService>? _opening;

  /// The service over the active database, built once per database.
  ///
  /// The instance is published only once its database is set: it used to be
  /// stored before the await, and a second caller in that window got a
  /// service whose `_db` was not yet initialized — every widget that loads
  /// its settings while another one does hit it once
  /// `DatabaseManager.getInstance` awaited one step more. A switch landing
  /// during the open starts it over ([_open]).
  static Future<SettingsService> getInstance() {
    final existing = _instance;
    if (existing != null) return Future.value(existing);
    final inFlight = _opening;
    if (inFlight != null) return inFlight;
    final opening = _open();
    _opening = opening;
    // Only this open's own entry is cleared: a reset during it may already
    // have let a newer open take the slot.
    void settle() {
      if (identical(_opening, opening)) _opening = null;
    }

    opening.then<void>((_) => settle(), onError: (Object _) => settle());
    return opening;
  }

  /// How many times [_open] starts over before it gives up on a database
  /// that keeps switching under it.
  static const int _openAttempts = 3;

  /// Publishes only a service whose database no switch overtook: one that
  /// did may be the closing database, and registering [reset] after the
  /// switch fired would keep that service past the reset meant to drop it.
  /// Every attempt re-checks the generation (final review X-6); past
  /// [_openAttempts] it throws rather than publish, as `SyncBindingService`
  /// does.
  static Future<SettingsService> _open() async {
    for (var attempt = 0; attempt < _openAttempts; attempt++) {
      final generation = DatabaseLifecycle.generation;
      final db = await AppDatabase.getInstance();
      final raced = _instance;
      if (raced != null) return raced;
      if (DatabaseLifecycle.generation != generation) continue;
      final service = SettingsService._().._db = db;
      _instance = service;
      DatabaseLifecycle.registerResetHandler(reset);
      return service;
    }
    throw StateError('the database switched while the settings were opened');
  }

  /// Binds the singleton to an arbitrary [AppDatabase], bypassing
  /// [AppDatabase.getInstance]'s `path_provider` lookup. Exists so tests can
  /// exercise the real DAO against `NativeDatabase.memory()`; never use it in
  /// app code — the singleton is what the [DatabaseLifecycle] reset contract
  /// is built on.
  ///
  /// [writeDebounce] shortens [defaultWriteDebounce] so a test can wait out a
  /// debounced write in real time instead of holding the suite for 400 ms.
  @visibleForTesting
  static SettingsService forTesting(AppDatabase db, {Duration? writeDebounce}) {
    if (_instance != null) return _instance!;
    final service = SettingsService._(writeDebounce: writeDebounce);
    service._db = db;
    _instance = service;
    DatabaseLifecycle.registerResetHandler(reset);
    return service;
  }

  /// Drops the cached singleton so the next [getInstance] rebinds to the
  /// currently-active [AppDatabase]. Invoked by [DatabaseLifecycle] when the
  /// active database changes.
  ///
  /// Also clears the static [FastingCalendar] configuration: it is derived
  /// entirely from settings rows this service owns, and would otherwise keep
  /// painting the previous database's practice.
  ///
  /// Debounced writes are dropped rather than flushed: this runs while the
  /// active database is being swapped, so a pending row would land in the
  /// wrong database — or in a closed one.
  static void reset() {
    _instance?._dropPendingWrites();
    _instance = null;
    _opening = null;
    FastingCalendar.resetConfiguration();
    EventAlerts.configureDefaultDayMinute(null);
    EventAlerts.configureShareAlerts(null);
  }

  /// Rows held back until the writes to them stop coming, keyed by settings
  /// key so a caller that changed one row never rewrites its neighbour — the
  /// editor page's old "save both font sizes on every tap" path did exactly
  /// that, and a preview size the user never touched was rewritten on every
  /// editor zoom.
  final Map<String, String> _pendingWrites = {};

  /// Runs from the *first* pending write rather than the latest one, so a
  /// deadline is never pushed back by a write to a different key.
  Timer? _writeTimer;

  /// Holds [key] back for [_writeDebounce], starting the deadline when the
  /// first row goes pending.
  ///
  /// The timer is deliberately not restarted on every call: the flush drains
  /// every pending key at once, so restarting it would let a key written
  /// repeatedly (a held +/- tap) starve a different key that has been pending
  /// since before the burst began.
  @override
  void _scheduleWrite(String key, String value) {
    _pendingWrites[key] = value;
    _writeTimer ??= Timer(_writeDebounce, () {
      _writeTimer = null;
      flushPendingWrites();
    });
  }

  /// Writes every debounced row now.
  ///
  /// Public because the editor page flushes on lifecycle pause and on dispose:
  /// a process killed inside the debounce window must not lose the size the
  /// user just set. Also called by [getEditorSettings], so a read can never
  /// see a value older than the last write.
  @override
  Future<void> flushPendingWrites() async {
    _writeTimer?.cancel();
    _writeTimer = null;
    if (_pendingWrites.isEmpty) return;
    // Drained before the first await: a second flush (or the timer firing
    // while this one is in flight) must not write the same row twice.
    final pending = Map<String, String>.of(_pendingWrites);
    _pendingWrites.clear();
    for (final entry in pending.entries) {
      await _db.userSettingsDao.setValue(entry.key, entry.value);
    }
  }

  void _dropPendingWrites() {
    _writeTimer?.cancel();
    _writeTimer = null;
    _pendingWrites.clear();
  }

  // A static is not inherited through a mixin, so the ones other libraries
  // call on [SettingsService] stay on the class itself, away from the areas
  // they belong to.

  /// How many icon keys the "Recently used" section remembers. Two rows of
  /// six at the picker's tile size — enough to hold a habit, short enough
  /// that the section never competes with the catalog below it.
  static const int recentIconLimit = 12;

  /// The alert options exactly as the app ships them, decoded through the same
  /// path a stored value takes.
  ///
  /// What reset-to-defaults writes. Derived rather than restated: a second
  /// spelling of `notify:10` on the settings page is a second answer to what
  /// "default" means, and the two would drift the first time one changed.
  static AlertSettings get shippedAlertSettings =>
      _decodeAlertSettings(const {});

  /// [getShareHiddenCategories] over [db] itself, in one statement: for the
  /// event and category loads, which map the rows of the database they
  /// hold — never the active one a switch may already have replaced — and
  /// for the shared reader's prune.
  static Future<Set<String>> shareHiddenCategoriesOf(AppDatabase db) async {
    final raw = await db.userSettingsDao.getValue(
      SettingsKeys.shareHiddenCategories,
    );
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const {};
      return Set.unmodifiable(decoded.whereType<String>());
    } on FormatException {
      return const {};
    }
  }

  /// [setShareHiddenCategories] over [db] itself.
  static Future<void> setShareHiddenCategoriesOf(
    AppDatabase db,
    Set<String> ids,
  ) async {
    if (ids.isEmpty) {
      await db.userSettingsDao.deleteValue(SettingsKeys.shareHiddenCategories);
      return;
    }
    await db.userSettingsDao.setValue(
      SettingsKeys.shareHiddenCategories,
      jsonEncode(ids.toList()..sort()),
    );
  }

  /// My own sort of each of the partner's folders, by folder id, in one
  /// statement over [db] itself: what `FolderStorageService` lays over a
  /// partner's folder as it maps it, and writes when the person sorts one.
  static Future<Map<String, PartnerFolderSort>> partnerFolderSortsOf(
    AppDatabase db,
  ) async => PartnerFolderSort.decodeAll(
    await db.userSettingsDao.getValue(SettingsKeys.shareFolderSorts),
  );

  /// Stores [sorts] over [db], deleting the row when none is left.
  static Future<void> setPartnerFolderSortsOf(
    AppDatabase db,
    Map<String, PartnerFolderSort> sorts,
  ) async {
    final raw = PartnerFolderSort.encodeAll(sorts);
    if (raw == null) {
      await db.userSettingsDao.deleteValue(SettingsKeys.shareFolderSorts);
      return;
    }
    await db.userSettingsDao.setValue(SettingsKeys.shareFolderSorts, raw);
  }
}
