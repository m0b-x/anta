import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What a relay message runs on the phone that no Dart suite can run — the
/// function the platform enters, and the call into the work plugin — held
/// here by reading the source (`docs/cloud-shared-freshness.md` §7): each
/// line below would build and pass every other suite with the wrong thing
/// in it, and only a phone would show the difference.
void main() {
  String code(String path) => File(path)
      .readAsStringSync()
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  group('the two functions the platform enters by a stored handle', () {
    /// The lines right above [declaration], comments and blanks left out.
    String aboveDeclaration(String path, String declaration) {
      final lines = File(path).readAsLinesSync();
      final at = lines.indexWhere((line) => line.startsWith(declaration));
      expect(at, isNonNegative, reason: declaration);
      return lines
          .sublist(0, at)
          .lastWhere((line) => line.trim().isNotEmpty)
          .trim();
    }

    test('each is kept through the release build\'s tree-shaking: without '
        'the pragma a debug build runs it all the same, and only a release '
        'one finds nothing behind the handle', () {
      expect(
        aboveDeclaration(
          'lib/services/push/push_messaging.dart',
          'Future<void> pushBackgroundHandler(RemoteMessage message)',
        ),
        "@pragma('vm:entry-point')",
      );
      expect(
        aboveDeclaration(
          'lib/services/shared_refresh/shared_refresh_entry.dart',
          'void sharedRefreshEntry()',
        ),
        "@pragma('vm:entry-point')",
      );
    });
  });

  group('the messaging plugin\'s engine (push review F13)', () {
    final source = code('lib/services/push/push_messaging.dart');

    /// The function the platform enters, from its name to its closing
    /// brace.
    String entryBody() {
      final entry = source.indexOf(
        'Future<void> pushBackgroundHandler(RemoteMessage message) async {',
      );
      expect(entry, isNonNegative);
      return source.substring(entry, source.indexOf('\n}', entry));
    }

    test('the function the platform enters hands the handler the resign', () {
      expect(entryBody(), contains('resign: resignPushEngine,'));
    });

    test('the resign is the alarm fork\'s own, for an engine that must '
        'never be where a ring is shown', () {
      final resign = source.indexOf('Future<void> resignPushEngine() async {');
      expect(resign, isNonNegative);
      final body = source.substring(resign, source.indexOf('\n}', resign));

      expect(body, contains('await Alarm.initWithoutPresenting();'));
      expect(body, contains('if (kIsWeb || !Platform.isAndroid) return;'));
    });

    test('it is asked before the message is looked at: an engine that only '
        'ever drops messages exists all the same', () {
      final handler = source.indexOf('Future<void> handleBackgroundPush(');
      expect(handler, isNonNegative);
      final resigned = source.indexOf('.timeout(resignBound)', handler);
      final looked = source.indexOf('sharedPokePair(data)', handler);

      expect(resigned, isNonNegative, reason: 'asked, and bounded');
      expect(resigned, lessThan(looked));
    });
  });

  group('a QA build\'s preferences are namespaced before an engine with no '
      'app first opens them (device pass, 2026-11-14)', () {
    // The resign opens the alarm fork's storage — the isolate's first
    // `getInstance()` — and the plugin refuses the prefix after it: in a QA
    // build every later step that asked for it threw, and the run ended
    // failed. No suite can turn the QA switch on, so the order is held by
    // reading the source.
    const namespaced = 'QaBootstrap.namespacePreferences();';

    test('the check\'s work: right after the availability guard, before '
        'the resign', () {
      final source = code(
        'lib/services/shared_refresh/shared_refresh_entry.dart',
      );
      final task = source.indexOf('Future<bool> sharedRefreshTask(');
      expect(task, isNonNegative);
      final guard = source.indexOf(
        'if (!SharedRefreshAvailability.isSupported) return true;',
        task,
      );
      final prefixed = source.indexOf(namespaced, task);
      final resigned = source.indexOf('await _resignAsPresenter(', task);

      expect(guard, isNonNegative);
      expect(prefixed, greaterThan(guard));
      expect(
        source.substring(guard, prefixed).trim().split('\n'),
        hasLength(1),
      );
      expect(resigned, greaterThan(prefixed));
      expect(namespaced.allMatches(source), hasLength(1));
    });

    test('the messaging plugin\'s handler: the first statement of the '
        'function the platform enters, before the handler that resigns', () {
      final source = code('lib/services/push/push_messaging.dart');
      final entry = source.indexOf(
        'Future<void> pushBackgroundHandler(RemoteMessage message) async {',
      );
      expect(entry, isNonNegative);
      final body = source.substring(entry, source.indexOf('\n}', entry));

      expect(
        body.split('\n')[1].trim(),
        namespaced,
        reason: 'the first statement',
      );
      expect(
        body.indexOf(namespaced),
        lessThan(body.indexOf('handleBackgroundPush(')),
      );
    });

    test('and the call is the once-per-isolate one: the plugin\'s own '
        '`setPrefix` is named nowhere else in lib', () {
      final bootstrap = code('lib/core/qa/qa_bootstrap.dart');
      expect(
        bootstrap,
        contains(
          'prefixOnce(() => SharedPreferences.setPrefix(QaMode.preferencesPrefix));',
        ),
      );
      expect(
        'SharedPreferences.setPrefix('.allMatches(bootstrap),
        hasLength(1),
      );
      final others = [
        for (final file in Directory('lib').listSync(recursive: true))
          if (file is File &&
              file.path.endsWith('.dart') &&
              !file.path.endsWith('qa_bootstrap.dart') &&
              code(file.path).contains('setPrefix('))
            file.path,
      ];
      expect(others, isEmpty);
    });
  });

  group('a message\'s work at the platform (push review F3a)', () {
    final source = code(
      'lib/services/shared_refresh/workmanager_shared_refresh_scheduler.dart',
    );
    final start = source.indexOf('Future<void> scheduleMessage(');
    final call = source.substring(start);

    test('never delayed, and expedited as it was asked: a delayed work is a '
        'plain one, which a phone asleep holds (second look, D1)', () {
      expect(start, isNonNegative);
      expect(call, isNot(contains('initialDelay')));
      expect(call, contains('expedited: expedited,'));
    });

    test('a message\'s hand-over takes the place of whatever stands under '
        'the name; only the work that runs asks for one behind itself '
        '(review of leg 12, F1) — appended, a work that had come back from '
        'a retry stood plain at the head with every later one behind it', () {
      expect(
        call.replaceAll(RegExp(r'\s+'), ' '),
        contains(
          'existingWorkPolicy: behindRunning '
          '? ExistingWorkPolicy.update '
          ': ExistingWorkPolicy.replace,',
        ),
      );
      expect('existingWorkPolicy:'.allMatches(call), hasLength(1));
      expect(call, contains('bool behindRunning = false,'));
      expect(call, contains('networkType: NetworkType.connected'));
      expect(
        'kSharedRefreshMessageWorkName,'.allMatches(call),
        hasLength(2),
        reason: 'the unique name and the task name',
      );
    });

    test('the handler never asks for one behind: its hand-overs supersede', () {
      final handler = code('lib/services/push/push_messaging.dart');
      expect(handler, isNot(contains('behindRunning')));
      final run = code('lib/services/shared_refresh/shared_refresh_app.dart');
      expect('behindRunning: true'.allMatches(run), hasLength(1));
    });
  });
}
