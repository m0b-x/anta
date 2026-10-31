import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/utils/settings_search.dart';
import 'package:anta/widgets/settings_section_list.dart';
import 'package:anta/widgets/slider_setting_row.dart';

/// `SliderSettingRow` exists so a calendar-settings slider does not fire a
/// haptic, an awaited settings write and a whole-page rebuild on every drag
/// tick — only once, when the drag commits. These tests pin the commit
/// contract directly against the widget's `Slider` callbacks (rather than
/// simulating a raw drag gesture, which cannot easily leave `onChangeEnd`
/// unfired to exercise the debounce fallback) and the caption swap that
/// keeps the value visible while a drag is in progress.
void main() {
  const captionStyle = TextStyle(fontSize: 12, color: Colors.grey);

  Future<int> pumpRow(
    WidgetTester tester, {
    required int value,
    required List<int> commits,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SliderSettingRow(
            title: const Text('Max day bars'),
            description: const Text('idle caption'),
            value: value,
            min: 1,
            max: 6,
            divisions: 5,
            captionStyle: captionStyle,
            draftCaption: (draft) => 'draft caption $draft',
            onCommit: commits.add,
          ),
        ),
      ),
    );
    return value;
  }

  Slider slider(WidgetTester tester) =>
      tester.widget<Slider>(find.byType(Slider));

  /// The caption the row shows, past the invisible templates its slot is
  /// sized by.
  Finder shown(String text) => find.text(text).hitTestable();
  Finder shownContaining(String text) =>
      find.textContaining(text).hitTestable();

  testWidgets('dragging updates the caption but never commits', (tester) async {
    final commits = <int>[];
    await pumpRow(tester, value: 3, commits: commits);
    final row = slider(tester);

    row.onChanged!(5);
    await tester.pump();

    expect(commits, isEmpty);
    expect(shown('draft caption 5'), findsOneWidget);
    expect(shown('idle caption'), findsNothing);
    // The thumb tracks the draft, not the committed prop.
    expect(tester.widget<Slider>(find.byType(Slider)).value, 5);
  });

  testWidgets('onChangeEnd commits exactly once with the final value', (
    tester,
  ) async {
    final commits = <int>[];
    await pumpRow(tester, value: 3, commits: commits);
    final row = slider(tester);

    row.onChanged!(4);
    await tester.pump();
    row.onChanged!(5);
    await tester.pump();
    row.onChangeEnd!(5);
    await tester.pump();

    expect(commits, [5]);
    // The caption falls back to the idle, pre-rendered description again.
    expect(shown('idle caption'), findsOneWidget);
    expect(shownContaining('draft caption'), findsNothing);
  });

  testWidgets('a debounce timer commits once when onChangeEnd never arrives', (
    tester,
  ) async {
    final commits = <int>[];
    await pumpRow(tester, value: 3, commits: commits);
    final row = slider(tester);

    row.onChanged!(6);
    await tester.pump();
    expect(commits, isEmpty);

    // Past the ~350ms fallback debounce; onChangeEnd is never called,
    // simulating an accessibility-driven change.
    await tester.pump(const Duration(milliseconds: 500));

    expect(commits, [6]);
    expect(shown('idle caption'), findsOneWidget);
  });

  testWidgets(
    'a timer commit followed by a late onChangeEnd does not double-commit',
    (tester) async {
      final commits = <int>[];
      await pumpRow(tester, value: 3, commits: commits);
      final row = slider(tester);

      row.onChanged!(6);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(commits, [6]);

      // A late onChangeEnd for the same drag must be a no-op: the draft
      // that guards a pending commit was already cleared by the timer.
      row.onChangeEnd!(6);
      await tester.pump();

      expect(commits, [6]);
    },
  );

  testWidgets('a draft made just before leaving the page is committed, not '
      'dropped with the timer', (tester) async {
    final commits = <int>[];
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('beneath')),
      ),
    );
    // No transitions: a page route's exit outlasts the 350 ms fallback, so
    // the timer would commit before the row is disposed and the case would
    // pass without the dispose path it pins.
    navigator.currentState!.push(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, _, _) => Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SliderSettingRow(
              title: const Text('Max day bars'),
              description: const Text('idle caption'),
              value: 3,
              min: 1,
              max: 6,
              divisions: 5,
              captionStyle: captionStyle,
              draftCaption: (draft) => 'draft caption $draft',
              // What the pages do, on a page that is leaving too.
              onCommit: (value) => setState(() => commits.add(value)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    slider(tester).onChanged!(5);
    await tester.pump();
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump();

    expect(find.byType(SliderSettingRow), findsNothing);
    expect(commits, [5]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a draft whose row leaves a page that stays — a fold, a '
      'search — is committed after the frame, so the page may rebuild', (
    tester,
  ) async {
    final commits = <int>[];
    var shown = true;
    late StateSetter setPage;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setPage = setState;
              return shown
                  ? SliderSettingRow(
                      title: const Text('Max day bars'),
                      description: const Text('idle caption'),
                      value: 3,
                      min: 1,
                      max: 6,
                      divisions: 5,
                      captionStyle: captionStyle,
                      draftCaption: (draft) => 'draft caption $draft',
                      // What the pages do: the page's own state changes.
                      onCommit: (value) => setState(() => commits.add(value)),
                    )
                  : const Text('folded');
            },
          ),
        ),
      ),
    );

    slider(tester).onChanged!(2);
    await tester.pump();
    setPage(() => shown = false);
    await tester.pump();
    await tester.pump();

    expect(commits, [2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the row is one node whose label is the title and whose value '
      'is the caption\'s sentence, each read once', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpRow(tester, value: 3, commits: []);

    var data = tester.getSemantics(find.byType(Slider)).getSemanticsData();
    expect(data.value, 'draft caption 3');
    expect(data.label, 'Max day bars');

    // Mid-drag the caption reads the draft and stays out of the label; the
    // bubble's number is labelled only while the bubble shows.
    slider(tester).onChanged!(5);
    await tester.pump();
    data = tester.getSemantics(find.byType(Slider)).getSemanticsData();
    expect(data.value, 'draft caption 5');
    expect(data.label, isNot(contains('draft caption')));
    await tester.pump(const Duration(milliseconds: 500));
    data = tester.getSemantics(find.byType(Slider)).getSemanticsData();
    expect(data.label, 'Max day bars');
    handle.dispose();
  });

  testWidgets('an external value change discards an in-progress draft', (
    tester,
  ) async {
    final commits = <int>[];
    await pumpRow(tester, value: 3, commits: commits);
    final row = slider(tester);

    row.onChanged!(5);
    await tester.pump();
    expect(shown('draft caption 5'), findsOneWidget);

    // The parent's "Reset to defaults" path: the committed `value` prop
    // changes from outside, independent of this row's own drag.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SliderSettingRow(
            title: const Text('Max day bars'),
            description: const Text('idle caption'),
            value: 2,
            min: 1,
            max: 6,
            divisions: 5,
            captionStyle: captionStyle,
            draftCaption: (draft) => 'draft caption $draft',
            onCommit: commits.add,
          ),
        ),
      ),
    );

    expect(shown('idle caption'), findsOneWidget);
    expect(shownContaining('draft caption'), findsNothing);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 2);
    expect(commits, isEmpty);
  });

  testWidgets('a caption that changes its line count mid-drag never moves the '
      'slider: the draft is drawn in the kit\'s caption role, in a slot as '
      'tall as the tallest caption', (tester) async {
    const idle =
        'An idle caption long enough to wrap onto more than one line here';
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SettingsSectionList(
            query: SettingsQuery.empty,
            sections: [
              SettingsSectionData(
                icon: Icons.tune,
                title: 'Section',
                entries: [
                  SettingsEntry(
                    title: 'Max day bars',
                    description: idle,
                    builder: (context, title, description) => SliderSettingRow(
                      title: title,
                      description: description,
                      value: 3,
                      min: 1,
                      max: 6,
                      divisions: 5,
                      captionStyle: captionStyle,
                      draftCaption: (draft) => 'draft $draft',
                      onCommit: (_) {},
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final before = tester.getRect(find.byType(Slider));
    final idleHeight = tester.getSize(shown(idle)).height;

    slider(tester).onChanged!(5);
    await tester.pump();

    final draft = shown('draft 5');
    expect(draft, findsOneWidget);
    expect(tester.getSize(draft).height, lessThan(idleHeight));
    final draftStyle = tester.widget<Text>(draft).style!;
    expect(draftStyle.fontSize, settingsCaptionStyle.fontSize);
    expect(draftStyle.height, settingsCaptionStyle.height);
    expect(tester.getRect(find.byType(Slider)), before);
  });
}
