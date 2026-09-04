import 'package:flutter/foundation.dart';

import '../constants/font_constants.dart';
import '../models/editor_settings.dart';
import '../models/utility_button_config.dart';
import '../services/settings_service.dart';

/// The editor page's settings, as one listenable value.
///
/// A page-owned [ChangeNotifier] rather than a BLoC on purpose: this sits on
/// the typing path — the span builder, the wrapper and the toolbar all read
/// [value] on every build — and an event/state round trip per keystroke-driven
/// rebuild buys nothing here. It calls [SettingsService] and nothing below it.
///
/// [loaded] is half of the editor-mount gate (B4): the page keeps its loading
/// skeleton up until both the note content and this bundle have landed, so the
/// `CodeEditor`'s `ValueKey` — derived from
/// [EditorSettings.liveMarkdownRendering] — is stable the first time it is
/// built and the editor is never remounted underneath the user.
class EditorSettingsController extends ChangeNotifier {
  /// [resolveSettings] exists so tests can hand in a service bound to an
  /// in-memory database; app code takes the default singleton.
  EditorSettingsController({
    Future<SettingsService> Function()? resolveSettings,
  }) : _resolveSettings = resolveSettings ?? SettingsService.getInstance;

  final Future<SettingsService> Function() _resolveSettings;

  /// Cached after the first resolve: the service is a singleton, and an
  /// `adjust*` must not pay for a lookup on every tap.
  SettingsService? _settings;

  EditorSettings _value = EditorSettings.defaults;
  bool _loaded = false;
  bool _disposed = false;

  /// [EditorSettings.defaults] until the first [reload] lands, so every reader
  /// has a complete value from the first build.
  EditorSettings get value => _value;

  /// Whether a bundle read has completed. Never returns to false.
  bool get loaded => _loaded;

  /// Whether the deprecated preview surface is reachable.
  bool get canPreview => _value.canPreview;

  /// Reads the whole bundle in one statement.
  ///
  /// Notifies when the value changed **or** when this was the first load: the
  /// page has to rebuild out of its loading skeleton even on an install whose
  /// stored settings all happen to equal the defaults.
  Future<void> reload() async {
    final settings = await _resolve();
    final next = await settings.getEditorSettings();
    // A reload that lands after the page is gone must not touch a disposed
    // notifier — the page starts one in `initState` and another on every
    // `didPopNext`, and either can outlive a fast back-navigation.
    if (_disposed) return;
    final changed = !_loaded || next != _value;
    _value = next;
    _loaded = true;
    if (changed) notifyListeners();
  }

  /// Steps the editor's text size by [direction] × [FontConstants.fontSizeStep],
  /// clamped to the allowed range. Already-clamped taps change nothing and
  /// notify nobody.
  void adjustEditorFontSize(int direction) =>
      _adjustFontSize(direction, preview: false);

  /// Steps the preview's text size. Separate from [adjustEditorFontSize] so
  /// zooming one surface never writes the other's row.
  void adjustPreviewFontSize(int direction) =>
      _adjustFontSize(direction, preview: true);

  /// Adopts a reordered toolbar utility row and persists it.
  ///
  /// The write goes through the service, but [value] is updated first and
  /// synchronously: the toolbar hands over the order the user just dragged,
  /// and re-reading it back from the database would let the row snap to its
  /// old position for however long the round trip takes.
  Future<void> setToolbarUtilityConfig(
    List<UtilityButtonConfig> configs,
  ) async {
    if (_disposed) return;
    _value = _value.copyWith(toolbarUtilityConfig: configs);
    notifyListeners();
    await (await _resolve()).setToolbarUtilityConfig(configs);
  }

  /// Forwards to the service so a size adjusted moments ago is persisted —
  /// the page calls this on lifecycle pause and on dispose. Inert before the
  /// service has been resolved: nothing can be pending on a service that was
  /// never reached.
  Future<void> flushPendingWrites() async {
    await _settings?.flushPendingWrites();
  }

  /// Late [reload] completions stop notifying from here on, and whatever a
  /// last-moment `adjust*` scheduled is written out.
  @override
  void dispose() {
    _disposed = true;
    flushPendingWrites();
    super.dispose();
  }

  void _adjustFontSize(int direction, {required bool preview}) {
    if (_disposed) return;
    final current = preview ? _value.previewFontSize : _value.editorFontSize;
    final next = (current + FontConstants.fontSizeStep * direction).clamp(
      FontConstants.minFontSize,
      FontConstants.maxFontSize,
    );
    if (next == current) return;
    _value = preview
        ? _value.copyWith(previewFontSize: next)
        : _value.copyWith(editorFontSize: next);
    notifyListeners();
    final settings = _settings;
    if (settings != null) {
      // Recorded synchronously, so a [flushPendingWrites] on the very next
      // line — which is what the page does on lifecycle pause — cannot run
      // before the tap it is supposed to be flushing.
      _writeFontSize(settings, next, preview: preview);
    } else {
      // A tap before the first [reload]: resolve, then write. One microtask
      // late, but never dropped.
      _resolveThenWriteFontSize(next, preview: preview);
    }
  }

  /// Unawaited by design: [value] already carries the new size, so nothing in
  /// the UI waits on the debounced write.
  void _writeFontSize(
    SettingsService settings,
    double size, {
    required bool preview,
  }) {
    if (preview) {
      settings.setPreviewFontSize(size);
    } else {
      settings.setEditorFontSize(size);
    }
  }

  Future<void> _resolveThenWriteFontSize(
    double size, {
    required bool preview,
  }) async {
    _writeFontSize(await _resolve(), size, preview: preview);
  }

  Future<SettingsService> _resolve() async {
    return _settings ??= await _resolveSettings();
  }
}
