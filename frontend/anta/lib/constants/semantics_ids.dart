/// Stable identifiers for the controls an automation driver targets.
///
/// Flutter exposes `Semantics.identifier` as the Android `resource-id` and the
/// iOS `accessibilityIdentifier`, separate from the label — so a driver can
/// find a control by id while the screen reader still announces the tooltip or
/// the row's text, and neither the locale nor a copy change moves the target.
///
/// These values are a contract with the driver: rename one and every script
/// that touches that control stops finding it. Add rather than rename, and
/// keep them kebab-case.
abstract final class SemanticsIds {
  /// The two halves of [LeadingNavPair], on every nested screen.
  static const String navBack = 'nav-back';
  static const String navMenu = 'nav-menu';

  /// The browser's create bar. `createNote` only exists below the root — a
  /// note cannot live at the database root, where that half is the importer.
  static const String createNote = 'create-note';
  static const String createFolder = 'create-folder';

  /// The browser bar's magnifier, and the query field it raises — the same
  /// field on the browser, the note lists and the search page.
  static const String searchOpen = 'search-open';
  static const String searchField = 'search-field';

  /// The note editor: the editing surface itself, the markdown toolbar under
  /// it, and the overflow menu that holds move/label/share/delete.
  static const String editorBody = 'editor-body';
  static const String editorToolbar = 'editor-toolbar';
  static const String editorMore = 'editor-more';

  /// Drawer destinations.
  static const String drawerSettings = 'drawer-settings';
  static const String drawerCalendar = 'drawer-calendar';

  /// The two smart rows above the root browser's folders. Named for the
  /// drawer because that is the vocabulary the driver was written against;
  /// the destinations themselves have never lived in the drawer.
  static const String drawerAllNotes = 'drawer-all-notes';
  static const String drawerRecent = 'drawer-recent';

  /// The primary pair of the shared confirmation and text-input dialogs, which
  /// every destructive action and every rename funnels through.
  static const String sheetConfirm = 'sheet-confirm';
  static const String sheetCancel = 'sheet-cancel';

  /// Settings entry points, which live as drawer rows.
  static const String settingsAppearance = 'settings-appearance';
  static const String settingsDatabases = 'settings-databases';

  /// The calendar's two controls that are not a day cell.
  static const String calendarToday = 'calendar-today';
  static const String calendarAddEvent = 'calendar-add-event';

  /// The colour-label swatch strip, in whichever sheet raised it.
  static const String labelPicker = 'label-picker';
}
