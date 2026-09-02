import 'package:flutter/foundation.dart';

import 'calendar_colors.dart';

/// Synchronous, in-memory view over the calendar's colour palette — the
/// built-in swatches plus whatever the user has added — populated by
/// `CalendarPaletteService`.
///
/// Mirrors the `CalendarCategories` pattern so every colour surface (the
/// accent row, the category editor, the fasting style sheet, the event and
/// template editors) resolves the same list in O(1) with no `await` and no
/// per-build allocation. [listenable] is what lets those surfaces repaint the
/// moment a colour is added or removed from any one of them.
abstract final class CalendarPalette {
  /// The swatches that ship with the app. Never stored, never deletable —
  /// editing this list reaches every install, including the ones that have
  /// customised their palette.
  static List<int> get defaults => CalendarColors.swatchPalette;

  static List<int> _custom = const [];
  static List<int> _all = CalendarColors.swatchPalette;
  static Set<int> _index = _defaultIndex;

  static final Set<int> _defaultIndex = Set.unmodifiable(
    CalendarColors.swatchPalette.toSet(),
  );

  /// Bumped on every [updateCache]. Doubles as the repaint signal for the
  /// pickers, which is why it is a notifier rather than a plain counter: a
  /// colour added from inside a bottom sheet has to reach the row that opened
  /// it, and the settings page's palette sheet has to reach both.
  static final ValueNotifier<int> listenable = ValueNotifier<int>(0);

  /// The recolour published by the most recent [updateCache], if that update
  /// was one — `(previous, next)`.
  ///
  /// Exists so a picker can follow a swatch the user recoloured *somewhere
  /// else*, which is reachable: the management sheet opens from inside a
  /// picker row. Without it, editing #123456 to #654321 there would leave the
  /// event still painted #123456, stranded as an orphan dot — the opposite of
  /// what "this swatch, but that shade" means. Valid only for the revision it
  /// arrived with; any other update clears it.
  static (int previous, int next)? get lastRecolor => _lastRecolor;
  static (int, int)? _lastRecolor;

  /// The user's own swatches, in the order they were added.
  static List<int> get custom => _custom;

  /// `#RRGGBB` — the only stable name a raw swatch has, and what someone
  /// carrying a colour between apps is looking for. One formatter, so the
  /// sheet's rows, the dots' accessible names and the picker cannot disagree.
  static String hexOf(int argb) =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// Built-ins first, then the user's own — the order every picker renders.
  static List<int> get all => _all;

  /// Whether [value] is one of the built-in swatches, i.e. cannot be edited
  /// or deleted.
  static bool isDefault(int value) => _defaultIndex.contains(value);

  /// Whether [value] is already offered, from either half of the palette.
  static bool contains(int value) => _index.contains(value);

  /// Replaces the cached custom set. Called by `CalendarPaletteService` after
  /// every load and every mutation.
  ///
  /// [recolored] carries the `(previous, next)` pair when this update *is* a
  /// recolour, and is cleared by every other update so it can never describe
  /// a stale revision.
  static void updateCache(List<int> custom, {(int, int)? recolored}) {
    _lastRecolor = recolored;
    _custom = List.unmodifiable(custom);
    _all = List.unmodifiable([...CalendarColors.swatchPalette, ...custom]);
    _index = Set.unmodifiable(_all.toSet());
    listenable.value++;
  }

  /// Drops back to a palette of built-ins only. Belongs to the service's
  /// `DatabaseLifecycle` reset: the custom swatches are rows of the database
  /// that just closed.
  static void resetCache() => updateCache(const []);
}
