import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/font_constants.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/editor_settings.dart';
import 'package:anta/models/utility_button_config.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

/// The editor page's settings bundle, against the real DAO.
///
/// Two things are being guarded here. First the cost: the page read nineteen
/// rows one await at a time, and it now has to finish before the editor can
/// mount at all — the `CodeEditor`'s `ValueKey` is derived from the live
/// rendering flag, so mounting early means mounting twice. The bundle is one
/// statement, and the round-trip cases are what keep its decoders from
/// drifting away from the single-row getters that share them.
///
/// Second the writes: font size is adjusted by repeated +/- taps, and each tap
/// used to write *both* size rows through the page's own DAO handle. Debounced
/// and keyed, a burst costs one write to one row — which is only safe if a
/// read can never see a stale value and a database switch can never carry a
/// pending row into the next database.
void main() {
  const debounce = Duration(milliseconds: 20);

  late AppDatabase db;
  late StatementCounter counter;
  late SettingsService settings;

  setUp(() async {
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
    settings = SettingsService.forTesting(db, writeDebounce: debounce);
  });

  tearDown(() async {
    // Drops anything still pending before the database goes away — the same
    // contract the app relies on when the active database is switched.
    SettingsService.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  test('the editor bundle costs one statement', () async {
    counter.reset();
    await settings.getEditorSettings();

    expect(counter.count, 1);
    expect(counter.selects, hasLength(1));
  });

  test('the bulk read is keyed, not a full-table read', () async {
    // `user_settings` also holds a `note_position_<id>` row per note the user
    // has opened, so a full-table read here would scale with the note count on
    // the one path that runs before the editor can mount.
    for (var i = 0; i < 200; i++) {
      await db.userSettingsDao.setValue(
        '${SettingsKeys.notePositionPrefix}note$i',
        '{"offset":0}',
      );
    }

    counter.reset();
    final bundle = await settings.getEditorSettings();

    final captured = counter.captured.single;
    expect(captured.args, isNotEmpty);
    expect(captured.sql, contains('IN'));
    expect(bundle, EditorSettings.defaults);
  });

  test('a virgin database resolves to the defaults', () async {
    final bundle = await settings.getEditorSettings();

    expect(bundle, EditorSettings.defaults);
    expect(bundle.toolbarUtilityConfig, UtilityButtonConfig.defaults());
    expect(bundle.editorFontSize, FontConstants.defaultFontSize);
    expect(bundle.previewFontSize, FontConstants.defaultFontSize);
    expect(bundle.canPreview, isFalse);
  });

  test('every field round-trips through its own setter', () async {
    final utilities = [
      for (final config in UtilityButtonConfig.defaults())
        config.id == UtilityButtonId.undo
            ? config.copyWith(isVisible: false)
            : config,
    ];

    // Every value differs from its default, so a field the bundle forgot to
    // decode reads back as the default and fails rather than passing by luck.
    await settings.setNoteSwipeEnabled(false);
    await settings.setShowStatsBar(false);
    await settings.setLiveMarkdownRendering(false);
    await settings.setShowLineNumbers(true);
    await settings.setWordWrap(false);
    await settings.setShowCursorLine(true);
    await settings.setAutoBreakLongLines(false);
    await settings.setPreviewWhenKeyboardHidden(true);
    await settings.setScrollCursorOnKeyboard(true);
    await settings.setPreviewModeEnabled(true);
    await settings.setShowPreviewScrollbar(true);
    await settings.setPreviewLinesPerChunk(25);
    await settings.setToolbarShortcutRatio(0.45);
    await settings.setToolbarSplitEnabled(false);
    await settings.setToolbarUtilityConfig(utilities);
    await settings.setVocabularySuggestionsEnabled(false);
    await settings.setVocabularyTriggerChar(';');
    await settings.setEditorFontSize(22);
    await settings.setPreviewFontSize(12);

    final bundle = await settings.getEditorSettings();

    expect(bundle.noteSwipeEnabled, isFalse);
    expect(bundle.showStatsBar, isFalse);
    expect(bundle.liveMarkdownRendering, isFalse);
    expect(bundle.showLineNumbers, isTrue);
    expect(bundle.wordWrap, isFalse);
    expect(bundle.showCursorLine, isTrue);
    expect(bundle.autoBreakLongLines, isFalse);
    expect(bundle.previewWhenKeyboardHidden, isTrue);
    expect(bundle.scrollCursorOnKeyboard, isTrue);
    expect(bundle.previewModeEnabled, isTrue);
    expect(bundle.showPreviewScrollbar, isTrue);
    expect(bundle.previewLinesPerChunk, 25);
    expect(bundle.toolbarShortcutRatio, 0.45);
    expect(bundle.toolbarSplitEnabled, isFalse);
    expect(bundle.toolbarUtilityConfig, utilities);
    expect(bundle.vocabularySuggestionsEnabled, isFalse);
    expect(bundle.vocabularyTriggerChar, ';');
    expect(bundle.editorFontSize, 22.0);
    expect(bundle.previewFontSize, 12.0);
    // Whole-object equality as well: a field left out of `props` would make
    // every field assertion above pass while the page's "did anything change"
    // check silently stopped seeing it.
    expect(
      bundle,
      EditorSettings(
        noteSwipeEnabled: false,
        showStatsBar: false,
        liveMarkdownRendering: false,
        showLineNumbers: true,
        wordWrap: false,
        showCursorLine: true,
        autoBreakLongLines: false,
        previewWhenKeyboardHidden: true,
        scrollCursorOnKeyboard: true,
        previewModeEnabled: true,
        showPreviewScrollbar: true,
        previewLinesPerChunk: 25,
        toolbarShortcutRatio: 0.45,
        toolbarSplitEnabled: false,
        toolbarUtilityConfig: utilities,
        vocabularySuggestionsEnabled: false,
        vocabularyTriggerChar: ';',
        editorFontSize: 22,
        previewFontSize: 12,
      ),
    );
  });

  test('the bundle agrees with every single-row getter', () async {
    await settings.setShowLineNumbers(true);
    await settings.setLiveMarkdownRendering(false);
    await settings.setToolbarShortcutRatio(0.6);
    await settings.setVocabularyTriggerChar('~');
    await settings.setPreviewLinesPerChunk(30);
    await settings.setEditorFontSize(20);
    await settings.setPreviewFontSize(24);

    final bundle = await settings.getEditorSettings();

    expect(bundle.noteSwipeEnabled, await settings.getNoteSwipeEnabled());
    expect(bundle.showStatsBar, await settings.getShowStatsBar());
    expect(
      bundle.liveMarkdownRendering,
      await settings.getLiveMarkdownRendering(),
    );
    expect(bundle.showLineNumbers, await settings.getShowLineNumbers());
    expect(bundle.wordWrap, await settings.getWordWrap());
    expect(bundle.showCursorLine, await settings.getShowCursorLine());
    expect(bundle.autoBreakLongLines, await settings.getAutoBreakLongLines());
    expect(
      bundle.previewWhenKeyboardHidden,
      await settings.getPreviewWhenKeyboardHidden(),
    );
    expect(
      bundle.scrollCursorOnKeyboard,
      await settings.getScrollCursorOnKeyboard(),
    );
    expect(bundle.previewModeEnabled, await settings.getPreviewModeEnabled());
    expect(
      bundle.showPreviewScrollbar,
      await settings.getShowPreviewScrollbar(),
    );
    expect(
      bundle.previewLinesPerChunk,
      await settings.getPreviewLinesPerChunk(),
    );
    expect(
      bundle.toolbarShortcutRatio,
      await settings.getToolbarShortcutRatio(),
    );
    expect(bundle.toolbarSplitEnabled, await settings.getToolbarSplitEnabled());
    expect(
      bundle.toolbarUtilityConfig,
      await settings.getToolbarUtilityConfig(),
    );
    expect(
      bundle.vocabularySuggestionsEnabled,
      await settings.getVocabularySuggestionsEnabled(),
    );
    expect(
      bundle.vocabularyTriggerChar,
      await settings.getVocabularyTriggerChar(),
    );
    expect(bundle.editorFontSize, await settings.getEditorFontSize());
    expect(bundle.previewFontSize, await settings.getPreviewFontSize());
  });

  group('a malformed row falls back per field', () {
    test('unparseable numbers and an over-long trigger', () async {
      await db.userSettingsDao.setValue(SettingsKeys.editorFontSize, 'abc');
      await db.userSettingsDao.setValue(SettingsKeys.previewFontSize, '');
      await db.userSettingsDao.setValue(
        SettingsKeys.toolbarShortcutRatio,
        'wide',
      );
      await db.userSettingsDao.setValue(
        SettingsKeys.previewLinesPerChunk,
        '12.5',
      );
      await db.userSettingsDao.setValue(
        SettingsKeys.vocabularyTriggerChar,
        '@@',
      );
      // A bool row that is neither 'true' nor 'false' reads as false, exactly
      // as `_decodeBool` has always resolved it for every other setting.
      await db.userSettingsDao.setValue(SettingsKeys.wordWrap, 'yes');

      final bundle = await settings.getEditorSettings();

      expect(bundle.editorFontSize, FontConstants.defaultFontSize);
      expect(bundle.previewFontSize, FontConstants.defaultFontSize);
      expect(
        bundle.toolbarShortcutRatio,
        SettingsKeys.defaultToolbarShortcutRatio,
      );
      expect(
        bundle.previewLinesPerChunk,
        SettingsKeys.defaultPreviewLinesPerChunk,
      );
      expect(
        bundle.vocabularyTriggerChar,
        SettingsKeys.defaultVocabularyTriggerChar,
      );
      expect(bundle.wordWrap, isFalse);
      // The single-row getters share the decoders, so they must land in the
      // same place rather than each inventing its own fallback.
      expect(await settings.getEditorFontSize(), FontConstants.defaultFontSize);
      expect(
        await settings.getPreviewFontSize(),
        FontConstants.defaultFontSize,
      );
      expect(
        await settings.getToolbarShortcutRatio(),
        SettingsKeys.defaultToolbarShortcutRatio,
      );
      expect(
        await settings.getVocabularyTriggerChar(),
        SettingsKeys.defaultVocabularyTriggerChar,
      );
    });

    test('a toolbar config row that is not JSON at all', () async {
      await db.userSettingsDao.setValue(
        SettingsKeys.toolbarUtilityConfig,
        '{not json',
      );

      // Never throws: an unreadable row must cost the user their button order,
      // not the whole editor open.
      expect(
        (await settings.getEditorSettings()).toolbarUtilityConfig,
        UtilityButtonConfig.defaults(),
      );
      expect(
        await settings.getToolbarUtilityConfig(),
        UtilityButtonConfig.defaults(),
      );
    });

    test('a toolbar config row that is JSON of the wrong shape', () async {
      await db.userSettingsDao.setValue(
        SettingsKeys.toolbarUtilityConfig,
        '[{"visible":true}]',
      );

      expect(
        (await settings.getEditorSettings()).toolbarUtilityConfig,
        UtilityButtonConfig.defaults(),
      );
      expect(
        await settings.getToolbarUtilityConfig(),
        UtilityButtonConfig.defaults(),
      );
    });
  });

  group('debounced font-size writes', () {
    test('a burst coalesces into one write of one row', () async {
      for (var size = 18.0; size <= 26.0; size += 2) {
        await settings.setEditorFontSize(size);
      }

      counter.reset();
      await settings.flushPendingWrites();

      expect(counter.count, 1);
      expect(
        await db.userSettingsDao.getValue(SettingsKeys.editorFontSize),
        '26.0',
      );
      // The page used to write both sizes on every tap; adjusting the editor
      // must leave a preview size the user never chose absent.
      expect(
        await db.userSettingsDao.getValue(SettingsKeys.previewFontSize),
        isNull,
      );
    });

    test('two pending keys are both written', () async {
      await settings.setEditorFontSize(22);
      await settings.setPreviewFontSize(12);

      counter.reset();
      await settings.flushPendingWrites();

      expect(counter.count, 2);
      expect(await settings.getEditorFontSize(), 22.0);
      expect(await settings.getPreviewFontSize(), 12.0);
    });

    test('the timer writes on its own when nobody flushes', () async {
      await settings.setEditorFontSize(24);

      expect(
        await db.userSettingsDao.getValue(SettingsKeys.editorFontSize),
        isNull,
        reason: 'the row is held back while the taps could still be coming',
      );

      await Future<void>.delayed(debounce * 5);

      expect(
        await db.userSettingsDao.getValue(SettingsKeys.editorFontSize),
        '24.0',
      );
    });

    test('a busy key never starves one pending since before it', () async {
      await settings.setEditorFontSize(24);

      // A held +/- tap on the *other* row. The deadline belongs to the
      // first pending write, not the latest one: restarting it on every
      // schedule would keep the editor size unwritten for as long as the
      // finger stays down, and the flush drains both keys anyway.
      String? editorRow;
      for (var i = 0; i < 20 && editorRow == null; i++) {
        await Future<void>.delayed(debounce ~/ 4);
        await settings.setPreviewFontSize(12 + i.toDouble());
        editorRow = await db.userSettingsDao.getValue(
          SettingsKeys.editorFontSize,
        );
      }

      expect(
        editorRow,
        '24.0',
        reason: 'the editor row was pending before the burst began',
      );
    });

    test('a flush with nothing pending issues no statement', () async {
      counter.reset();
      await settings.flushPendingWrites();

      expect(counter.count, 0);
    });

    test('the bundle flushes before it reads', () async {
      await settings.setEditorFontSize(22);

      // Without the flush this reads 16: the page re-reads the bundle on the
      // way back from the settings page, moments after the last +/- tap.
      expect((await settings.getEditorSettings()).editorFontSize, 22.0);
      expect(
        await db.userSettingsDao.getValue(SettingsKeys.editorFontSize),
        '22.0',
      );
    });

    test('reset drops a pending write instead of letting it land', () async {
      await settings.setEditorFontSize(28);

      // What a database switch does: the row must not reach the *next*
      // database, and must not reach a closed one either.
      SettingsService.reset();
      final rebound = SettingsService.forTesting(db, writeDebounce: debounce);
      await Future<void>.delayed(debounce * 5);

      expect(
        await db.userSettingsDao.getValue(SettingsKeys.editorFontSize),
        isNull,
      );
      expect(await rebound.getEditorFontSize(), FontConstants.defaultFontSize);
    });
  });
}
