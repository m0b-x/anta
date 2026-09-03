import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/main.dart';

/// Flutter's release-mode [ErrorWidget] is a textless `RenderErrorBox` that
/// expands to fill its parent and absorbs every tap inside it, so one build
/// exception inside a bottom sheet reads as a blank, dead sheet — the report
/// this replacement exists for.
///
/// The two things that matter are therefore: it says something, and it stays
/// small. It also runs with no inherited theme, no `Directionality` and no
/// `BuildContext` to resolve localizations from, which is why every test here
/// pumps it bare rather than inside a `MaterialApp`.
void main() {
  const details = FlutterErrorDetails(
    exception: 'Null check operator used on a null value',
    library: 'widgets library',
  );

  testWidgets('renders the localized title with no ambient theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 320,
          height: 240,
          child: buildAppErrorWidget(details),
        ),
      ),
    );

    final en = lookupAppLocalizations(const Locale('en'));
    expect(find.text(en.renderErrorTitle), findsOneWidget);
    expect(
      find.text(en.renderErrorDetail(details.exceptionAsString())),
      findsOneWidget,
    );
  });

  testWidgets('stays smaller than a tight parent instead of filling it', (
    tester,
  ) async {
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 320,
          height: 240,
          child: buildAppErrorWidget(details),
        ),
      ),
    );

    final box = tester.getSize(find.byType(Material));
    expect(box.width, lessThanOrEqualTo(320));
    expect(
      box.height,
      lessThan(240),
      reason: 'the placeholder expanded to fill its parent, like the default',
    );
  });

  testWidgets('truncates a long exception', (tester) async {
    final long = FlutterErrorDetails(
      exception: 'x' * 5000,
      library: 'widgets library',
    );
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 320,
          height: 240,
          child: buildAppErrorWidget(long),
        ),
      ),
    );

    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(text.data, contains('…'));
    expect(text.data!.length, lessThan(400));
  });

  testWidgets('falls back to English on an unsupported device locale', (
    tester,
  ) async {
    tester.platformDispatcher.localeTestValue = const Locale('ja');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);

    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 320,
          height: 240,
          child: buildAppErrorWidget(details),
        ),
      ),
    );

    expect(
      find.text(lookupAppLocalizations(const Locale('en')).renderErrorTitle),
      findsOneWidget,
    );
  });

  testWidgets('installErrorHooks replaces the default builder', (tester) async {
    final previousBuilder = ErrorWidget.builder;
    final previousOnError = FlutterError.onError;

    installErrorHooks();
    final built = ErrorWidget.builder(details);
    final onError = FlutterError.onError;

    // Restored inside the body: the test framework checks both globals as
    // soon as the body returns, before any `addTearDown` runs.
    ErrorWidget.builder = previousBuilder;
    FlutterError.onError = previousOnError;

    expect(built, isA<Directionality>());
    expect(onError, isNot(same(previousOnError)));
  });
}
