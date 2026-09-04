import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/font_constants.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/controllers/editor_settings_controller.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/editor_settings.dart';
import 'package:anta/models/utility_button_config.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

/// The editor page's settings controller, over the real service and DAO.
///
/// The notification count is the point of most of these cases. The page
/// rebuilds on every notify and re-derives work from it — preview chunking,
/// the vocabulary trigger, whether the preview is still reachable — so a
/// controller that notified on an unchanged `didPopNext` re-read would repaint
/// and re-dispatch on every return from another page. And the *first* load has
/// to notify even when nothing differs from the defaults, because that is what
/// takes the page out of its loading skeleton and lets the editor mount.
void main() {
  const debounce = Duration(milliseconds: 20);

  late AppDatabase db;
  late StatementCounter counter;
  late SettingsService settings;
  late EditorSettingsController controller;
  late int notifications;

  setUp(() async {
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
    settings = SettingsService.forTesting(db, writeDebounce: debounce);
    controller = EditorSettingsController(
      resolveSettings: () async => settings,
    );
    notifications = 0;
    controller.addListener(() => notifications++);
  });

  tearDown(() async {
    await controller.flushPendingWrites();
    controller.dispose();
    SettingsService.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  test('the first reload costs one select and always notifies', () async {
    counter.reset();
    await controller.reload();

    expect(counter.count, 1);
    expect(counter.selects, hasLength(1));
    expect(controller.loaded, isTrue);
    // Nothing differs from the defaults, and it still has to notify: `loaded`
    // flipping is what dismisses the page's loading skeleton.
    expect(controller.value, EditorSettings.defaults);
    expect(notifications, 1);
  });

  test('a second reload with unchanged values does not notify', () async {
    await controller.reload();
    await controller.reload();

    expect(notifications, 1);
  });

  test('a reload picks up a value changed underneath it', () async {
    await controller.reload();
    await settings.setShowLineNumbers(true);

    await controller.reload();

    expect(notifications, 2);
    expect(controller.value.showLineNumbers, isTrue);
  });

  test('stored flags mirror into the value', () async {
    await settings.setLiveMarkdownRendering(false);
    await settings.setShowStatsBar(false);
    await settings.setPreviewLinesPerChunk(25);
    await settings.setVocabularyTriggerChar(';');

    await controller.reload();

    expect(controller.value.liveMarkdownRendering, isFalse);
    expect(controller.value.showStatsBar, isFalse);
    expect(controller.value.previewLinesPerChunk, 25);
    expect(controller.value.vocabularyTriggerChar, ';');
    // Live rendering off is the second route to the deprecated preview: with
    // raw markdown in the editor it is the only rendered surface left.
    expect(controller.canPreview, isTrue);
  });

  test('the value is the defaults before the first reload lands', () {
    expect(controller.loaded, isFalse);
    expect(controller.value, EditorSettings.defaults);
    expect(controller.canPreview, EditorSettings.defaults.canPreview);
  });

  test('a reordered utility row lands in the value before the write', () async {
    await controller.reload();
    notifications = 0;
    final reordered = UtilityButtonConfig.defaults().reversed.toList(
      growable: false,
    );

    final pending = controller.setToolbarUtilityConfig(reordered);

    // The toolbar drops the order the user just dragged; it has to be
    // readable back immediately or the row snaps to its old position for
    // the length of the round trip.
    expect(controller.value.toolbarUtilityConfig, reordered);
    expect(notifications, 1);

    await pending;

    expect(
      await db.userSettingsDao.getValue(SettingsKeys.toolbarUtilityConfig),
      UtilityButtonConfig.encode(reordered),
    );
    // And a re-read agrees, so no later `didPopNext` reload can undo it.
    await controller.reload();
    expect(controller.value.toolbarUtilityConfig, reordered);
  });

  group('font size', () {
    test('an editor adjust steps, notifies and writes only its row', () async {
      await controller.reload();
      notifications = 0;

      controller.adjustEditorFontSize(1);

      expect(
        controller.value.editorFontSize,
        FontConstants.defaultFontSize + FontConstants.fontSizeStep,
      );
      expect(notifications, 1);

      await controller.flushPendingWrites();

      expect(
        await db.userSettingsDao.getValue(SettingsKeys.editorFontSize),
        '18.0',
      );
      expect(
        await db.userSettingsDao.getValue(SettingsKeys.previewFontSize),
        isNull,
      );
    });

    test('a preview adjust steps, notifies and writes only its row', () async {
      await controller.reload();
      notifications = 0;

      controller.adjustPreviewFontSize(-1);

      expect(
        controller.value.previewFontSize,
        FontConstants.defaultFontSize - FontConstants.fontSizeStep,
      );
      expect(notifications, 1);

      await controller.flushPendingWrites();

      expect(
        await db.userSettingsDao.getValue(SettingsKeys.previewFontSize),
        '14.0',
      );
      expect(
        await db.userSettingsDao.getValue(SettingsKeys.editorFontSize),
        isNull,
      );
    });

    test('the maximum clamps without notifying', () async {
      await controller.reload();
      while (controller.value.editorFontSize < FontConstants.maxFontSize) {
        controller.adjustEditorFontSize(1);
      }
      expect(controller.value.editorFontSize, FontConstants.maxFontSize);

      notifications = 0;
      controller.adjustEditorFontSize(1);

      expect(notifications, 0);
      expect(controller.value.editorFontSize, FontConstants.maxFontSize);
    });

    test('the minimum clamps without notifying', () async {
      await controller.reload();
      while (controller.value.previewFontSize > FontConstants.minFontSize) {
        controller.adjustPreviewFontSize(-1);
      }
      expect(controller.value.previewFontSize, FontConstants.minFontSize);

      notifications = 0;
      controller.adjustPreviewFontSize(-1);

      expect(notifications, 0);
      expect(controller.value.previewFontSize, FontConstants.minFontSize);
    });

    test('an unflushed adjust survives a reload', () async {
      await controller.reload();
      controller.adjustEditorFontSize(1);

      // The bundle read flushes first, so the re-read cannot hand back the
      // size the user just replaced.
      await controller.reload();

      expect(controller.value.editorFontSize, 18.0);
    });

    test('an adjust before the first reload is not lost', () async {
      controller.adjustEditorFontSize(1);

      expect(controller.value.editorFontSize, 18.0);
      // The service was not resolved yet, so the write is one microtask behind
      // the tap. It still has to land.
      await Future<void>.delayed(Duration.zero);
      await controller.flushPendingWrites();

      expect(
        await db.userSettingsDao.getValue(SettingsKeys.editorFontSize),
        '18.0',
      );
    });
  });

  test('a reload completing after dispose does not notify', () async {
    final gate = Completer<void>();
    final abandoned = EditorSettingsController(
      resolveSettings: () async {
        await gate.future;
        return settings;
      },
    );
    var abandonedNotifications = 0;
    abandoned.addListener(() => abandonedNotifications++);

    final pending = abandoned.reload();
    abandoned.dispose();
    gate.complete();
    await pending;

    expect(abandonedNotifications, 0);
    expect(abandoned.loaded, isFalse);
  });
}
