@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/event_editor_sheet.dart';

import '../widgets/support/layout_errors.dart';
import 'support/golden_matrix.dart';

/// The event editor's form for a new event on a fixed day, harnessed as
/// `test/widgets/event_editor_title_test.dart` harnesses it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MarkdownBarBloc barBloc;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_golden_event_editor');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    // Opened here, in the real async zone: a first open inside a test body
    // would wait on an isolate the fake clock never lets answer.
    await SettingsService.getInstance();
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    barBloc = MarkdownBarBloc(
      barService: await MarkdownBarService.getInstance(),
    );
  });

  tearDown(() async {
    await barBloc.close();
  });

  for (final cell in goldenCells) {
    testWidgets('event editor, ${cell.label}', (tester) async {
      setGoldenSurface(tester, cell);
      final errors = await layoutErrorsDuring(() async {
        await tester.pumpWidget(
          goldenApp(
            cell,
            home: Scaffold(
              body: BlocProvider<MarkdownBarBloc>.value(
                value: barBloc,
                child: EventEditorSheet(defaultDate: DateTime.utc(2026, 8, 20)),
              ),
            ),
          ),
        );
        // The sheet reads its settings from the app's database, which
        // answers on a background isolate `FakeAsync` cannot advance: real
        // time and frames are interleaved until the reads have landed.
        for (var i = 0; i < 12; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 5));
        }
        await tester.pumpAndSettle();
      });

      expect(errors, isEmpty);
      await expectGolden('event_editor', cell);
    });
  }
}
