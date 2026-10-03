import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/removed_holidays_sheet.dart';

/// One row of the removed-holidays list, as printed.
typedef RemovedHolidayRow = ({String name, String date});

/// Drives the removed-holidays sheet — [RemovedHolidaysSheet] — for the
/// suites: they say what the user does and read what the sheet shows, and
/// never name a widget type.
///
/// The seam is what let the Tier 3 rebuild of the sheet
/// (`docs/calendar-language-tier-3-roadmap.md`, slice 5) land under the
/// suite that pinned the old chrome: the rebuild rewrote this file and left
/// the bodies alone, but for the behaviour that record changes on purpose.
/// The finders are the sub-sheet's: the ✕ by its id, one read row per
/// holiday with its Restore as the row's second target by its id, the
/// spinner while the list loads, the caption while it is empty, the
/// confirmation as the overlay bar above the sheet.
///
/// The sheet reads its rows from the service it is handed, which has no
/// in-memory binding and answers from the app database's background
/// isolate — a round trip the fake-async zone a widget test runs in never
/// completes. So [show] stops at the first frame, and [settle] drains the
/// read through `runAsync` (the memory note: tap on the fake clock, drain
/// under `runAsync`, never tap inside it).
class RemovedHolidaysRobot {
  const RemovedHolidaysRobot(this.tester);

  final WidgetTester tester;

  static const String _openLabel = 'open';

  Finder get _sheet => find.byType(RemovedHolidaysSheet);

  Finder _in(Finder matching) =>
      find.descendant(of: _sheet, matching: matching);

  Finder _byId(String id) => _in(find.bySemanticsIdentifier(id));

  AppLocalizations get _l10n => AppLocalizations.of(tester.element(_sheet))!;

  Finder get _rows => _in(find.byType(FormPickerRow));

  /// The row of the holiday named [name].
  Finder _row(String name) =>
      _in(find.byWidgetPredicate((w) => w is FormPickerRow && w.label == name));

  /// The overlay bar a message is raised in: a live region outside the
  /// sheet, which draws none of its own.
  Finder get _overlayBar => find.byWidgetPredicate(
    (w) =>
        w is Semantics &&
        w.properties.liveRegion == true &&
        find
            .ancestor(of: find.byWidget(w), matching: _sheet)
            .evaluate()
            .isEmpty,
  );

  /// Whether [finder] matches, with the strength of the `findsOneWidget` /
  /// `findsNothing` pair it stands for: a second match fails the test
  /// whichever answer the caller expected.
  bool _shown(Finder finder) {
    final matches = finder.evaluate().length;
    if (matches > 1) {
      fail('Expected at most one match, found $matches: $finder');
    }
    return matches == 1;
  }

  /// Opens the sheet the way Calendar settings does — through `show`, from a
  /// button on a page — and stops at its first frames, with the read still
  /// in flight: `pumpAndSettle` would spin on the loading indicator for
  /// ever. [settle] finishes the job.
  Future<void> show(
    PublicHolidayService service, {
    Locale locale = const Locale('en'),
    double? textScale,
    Size? surface,
  }) async {
    if (surface != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = surface;
    }
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: textScale == null
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => RemovedHolidaysSheet.show(context, service),
              child: const Text(_openLabel),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text(_openLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Lets the service answer: the real event loop runs in short slices
  /// until [done] holds, then the frames the answer scheduled are drawn.
  Future<void> _drain(bool Function() done) async {
    for (var i = 0; i < 50; i++) {
      if (done()) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    if (!done()) fail('The service never answered');
    await tester.pumpAndSettle();
  }

  /// Waits for the list to load.
  Future<void> settle() => _drain(() => !isLoading);

  bool get isOpen => _shown(_sheet);

  bool get isLoading => _shown(_in(find.byType(CircularProgressIndicator)));

  bool get isEmpty => _shown(_in(find.text(_l10n.removedHolidaysEmpty)));

  /// The rows, top to bottom: the holiday's name and the date it was removed
  /// on, as printed.
  List<RemovedHolidayRow> get rows => [
    for (final row in tester.widgetList<FormPickerRow>(_rows))
      (name: row.label, date: row.value!),
  ];

  /// The id the Restore of the row named [name] carries.
  String restoreId(String name) =>
      tester.widget<FormPickerRow>(_row(name)).trailingButton!.identifier!;

  /// Restore on the row of [name], and the service's answer drained: the
  /// row goes and a confirmation comes up, or the row stays and a failure
  /// does — either way the sheet has said something.
  Future<void> restore(String name) async {
    await tester.tap(find.bySemanticsIdentifier(restoreId(name)));
    await tester.pump();
    await _drain(() => message != null || !_shown(_row(name)));
  }

  /// The message on screen, or null.
  String? get message {
    final bar = _overlayBar;
    if (!_shown(bar)) return null;
    return tester
        .widget<Text>(find.descendant(of: bar, matching: find.byType(Text)))
        .data;
  }

  /// Whether the message is where a finger can reach it — above the sheet,
  /// not on the page under it.
  bool get messageReachable {
    final text = message;
    return text != null && _shown(find.text(text).hitTestable());
  }

  /// Whether a `Scaffold` snackbar is up anywhere — the old path, drawn
  /// under the sheet.
  bool get scaffoldSnackbarShown => _shown(find.byType(SnackBar));

  // --- Geometry and semantics ------------------------------------------------

  /// The semantics of the control carrying [id].
  SemanticsData nodeOf(String id) =>
      tester.getSemantics(_byId(id)).getSemanticsData();

  /// The semantics of the read row named [name] — its one merged node, the
  /// name and the date in its label.
  SemanticsData rowNode(String name) =>
      tester.getSemantics(_in(find.text(name))).getSemanticsData();

  /// The on-screen rect of the control carrying [id].
  Rect targetOf(String id) => tester.getRect(_byId(id));

  Rect rowRect(String name) => tester.getRect(_row(name));

  Rect get sheetRect => tester.getRect(_sheet);

  Rect nameRect(String name) => tester.getRect(_in(find.text(name)));

  Rect dateRect(String name) {
    final date = tester.widget<FormPickerRow>(_row(name)).value!;
    return tester.getRect(_in(find.text(date)));
  }

  /// Whether the row named [name] draws its name and its date whole: the
  /// name on as many lines as it needs, the date within its two, nothing cut
  /// by an ellipsis, both inside the sheet's width.
  bool rowWhole(String name) {
    final date = tester.widget<FormPickerRow>(_row(name)).value!;
    final label = _in(find.text(name));
    if (tester.widget<Text>(label).maxLines != null) return false;
    for (final text in [label, _in(find.text(date))]) {
      if (tester.renderObject<RenderParagraph>(text).didExceedMaxLines) {
        return false;
      }
      final rect = tester.getRect(text);
      final sheet = sheetRect;
      if (rect.left < sheet.left || rect.right > sheet.right) return false;
    }
    return true;
  }

  // --- Leaving ---------------------------------------------------------------

  Future<void> close() async {
    await tester.tap(_byId(SemanticsIds.removedHolidaysClose));
    await tester.pumpAndSettle();
  }

  /// A tap on the scrim above the sheet.
  Future<void> tapBarrier() async {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(size.width / 2, 8));
    await tester.pumpAndSettle();
  }

  Future<void> systemBack() async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }
}
