import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/widgets/event_editor_sheet.dart';

/// The editor sheet is reached two ways, and only one of them has something
/// behind it. `showBack` is what tells the two apart: the detail sheet's path
/// gets a back button that returns there, and every direct path (FAB, agenda
/// pencil, template quick-add) keeps the close button that ends the trip.
///
/// Back **discards, exactly like close** — there is no dirty tracking in this
/// sheet — which is why back *replaces* close rather than joining it. Two
/// adjacent buttons that discard identically and differ only in destination is
/// a distinction too fine to hang a second icon on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MarkdownBarBloc barBloc;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_event_editor_back');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    final barService = await MarkdownBarService.getInstance();
    barBloc = MarkdownBarBloc(barService: barService);
  });

  tearDown(() async {
    await barBloc.close();
  });

  final day = DateTime.utc(2026, 8, 25);
  final event = CalendarEvent(
    id: 'e1',
    title: 'Leg day',
    categoryId: 'gym',
    startDate: day,
    rule: const DailyRecurrence(),
  );

  Future<List<EventEditorResult?>> openEditor(
    WidgetTester tester, {
    required bool showBack,
  }) async {
    final results = <EventEditorResult?>[];
    await tester.pumpWidget(
      // Above the `MaterialApp`, as `main.dart` provides it — the sheet is a
      // route, so a provider inside `home` sits below it in the tree.
      BlocProvider<MarkdownBarBloc>.value(
        value: barBloc,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  results.add(
                    await EventEditorSheet.show(
                      context,
                      defaultDate: day,
                      initialEvent: event,
                      occurrenceDay: day,
                      showBack: showBack,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('the back button reports EventEditorBack', (tester) async {
    final results = await openEditor(tester, showBack: true);

    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(
      find.byIcon(Icons.close_rounded),
      findsNothing,
      reason: 'back replaces close rather than joining it',
    );

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(results.single, isA<EventEditorBack>());
  });

  testWidgets('without a sheet behind it, close still ends the trip', (
    tester,
  ) async {
    final results = await openEditor(tester, showBack: false);

    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(
      results.single,
      isNull,
      reason: 'null is what closes the whole stack',
    );
  });

  testWidgets('the system back gesture lands where the back button lands', (
    tester,
  ) async {
    final results = await openEditor(tester, showBack: true);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      results.single,
      isA<EventEditorBack>(),
      reason:
          'the gesture and the button must not disagree about what back means',
    );
  });

  testWidgets(
    'the system back gesture still cancels a directly-opened editor',
    (tester) async {
      final results = await openEditor(tester, showBack: false);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(results.single, isNull);
    },
  );
}
