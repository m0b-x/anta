import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:anta/widgets/alert_sound_sheet.dart';

/// The chooser is the one surface both the alert editor and the Calendar
/// settings row open, so what it offers has to depend on the **platform**, not
/// on which of the two opened it — except for the one choice only an alert can
/// make, which is deferring to the app setting.
///
/// Every test binds its own gateway through GetIt, because that is how the
/// sheet asks what the phone can do: a build with none (desktop, and most of
/// this suite) must simply show fewer options rather than fail.
void main() {
  tearDown(() async {
    if (GetIt.I.isRegistered<AlertGateway>()) {
      await GetIt.I.unregister<AlertGateway>();
    }
  });

  /// The sheet's result arrives long after [openSheet] returns, so it is
  /// handed back in a holder rather than as a value — the
  /// `alert_editor_sheet_test` shape.
  Future<_Holder> openSheet(
    WidgetTester tester, {
    String? value,
    bool allowInherit = false,
  }) async {
    final result = _Holder();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result.value = await AlertSoundSheet.show(
                  context,
                  value: value,
                  allowInherit: allowInherit,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('the phone options are hidden where nothing can serve them', (
    tester,
  ) async {
    // No gateway at all — desktop, and every widget suite. Offering a button
    // that opens nothing is worse than not offering it.
    await openSheet(tester);

    expect(find.text('ANTA sound'), findsOneWidget);
    expect(find.text("Phone's default alarm"), findsNothing);
    expect(find.text('Choose from phone'), findsNothing);
  });

  testWidgets('a gateway that supports them shows both', (tester) async {
    GetIt.I.registerSingleton<AlertGateway>(const _PhoneSoundGateway());
    await openSheet(tester);

    expect(find.text("Phone's default alarm"), findsOneWidget);
    expect(find.text('Choose from phone'), findsOneWidget);
  });

  testWidgets('"Use the app setting" is absent on the settings variant', (
    tester,
  ) async {
    // The settings row *is* the app setting; offering it there would be a
    // choice that points at itself.
    await openSheet(tester);

    expect(find.text('Use the app setting'), findsNothing);
  });

  testWidgets('"Use the app setting" is offered on the editor variant', (
    tester,
  ) async {
    await openSheet(tester, allowInherit: true);

    expect(find.text('Use the app setting'), findsOneWidget);
  });

  testWidgets('picking the ANTA sound reports the empty string', (
    tester,
  ) async {
    // `''`, not null: on an alert that is "the ANTA sound whatever the setting
    // says", which is a different answer from deferring to it.
    final result = await openSheet(tester, allowInherit: true);
    await tester.tap(find.text('ANTA sound'));
    await tester.pumpAndSettle();

    expect(result.value, isA<AlertSoundPicked>());
    expect((result.value! as AlertSoundPicked).value, '');
  });

  testWidgets('picking "Use the app setting" reports null', (tester) async {
    final result = await openSheet(
      tester,
      value: 'system:default',
      allowInherit: true,
    );
    await tester.tap(find.text('Use the app setting'));
    await tester.pumpAndSettle();

    expect((result.value! as AlertSoundPicked).value, isNull);
  });

  testWidgets('a sound this phone cannot resolve says so, never its URI', (
    tester,
  ) async {
    // What a restore from another phone leaves behind. A raw `content://` URI
    // means nothing to anyone, and the honest thing to say is what will
    // actually ring.
    GetIt.I.registerSingleton<AlertGateway>(const _PhoneSoundGateway());
    await openSheet(tester, value: 'content://media/does-not-exist');

    expect(find.text('Not on this phone — plays the ANTA sound'), findsOneWidget);
    expect(find.textContaining('content://'), findsNothing);
  });

  testWidgets('a resolvable sound is named by the phone', (tester) async {
    GetIt.I.registerSingleton<AlertGateway>(
      const _PhoneSoundGateway(title: 'Oxygen'),
    );
    await openSheet(tester, value: 'content://media/7');

    expect(find.text('Oxygen'), findsOneWidget);
  });

  testWidgets('a device with no picker is reported, not swallowed', (
    tester,
  ) async {
    // The sheet cannot raise the snackbar itself — a `SnackBar` belongs to a
    // `Scaffold`, which sits below a modal route — so it closes with the fact
    // and the caller says it.
    GetIt.I.registerSingleton<AlertGateway>(const _NoPickerGateway());
    final result = await openSheet(tester);
    await tester.tap(find.text('Choose from phone'));
    await tester.pumpAndSettle();

    expect(result.value, isA<AlertSoundPickerMissing>());
  });

  testWidgets('a cancelled pick leaves the sheet exactly where it was', (
    tester,
  ) async {
    GetIt.I.registerSingleton<AlertGateway>(const _PhoneSoundGateway());
    final result = await openSheet(tester, value: '');
    await tester.tap(find.text('Choose from phone'));
    await tester.pumpAndSettle();

    expect(result.value, isNull);
    expect(find.byType(AlertSoundSheet), findsOneWidget);
  });

  testWidgets('the row label is one line in every state', (tester) async {
    // The static both call sites render their trailing line from. It has to
    // answer before the phone does, or the row changes height under the finger
    // that opened it — and it must never fall back to the raw URI.
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context)!;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(AlertSoundSheet.labelFor(l10n, null), 'Use the app setting');
    expect(AlertSoundSheet.labelFor(l10n, ''), 'ANTA sound');
    expect(
      AlertSoundSheet.labelFor(l10n, 'system:default'),
      "Phone's default alarm",
    );
    // Before the phone has answered, and after it has answered "no".
    expect(
      AlertSoundSheet.labelFor(l10n, 'content://media/7'),
      'Sound from phone',
    );
    expect(
      AlertSoundSheet.labelFor(l10n, 'content://media/7', titleResolved: true),
      'Not on this phone — plays the ANTA sound',
    );
    expect(
      AlertSoundSheet.labelFor(
        l10n,
        'content://media/7',
        title: 'Oxygen',
        titleResolved: true,
      ),
      'Oxygen',
    );
    // Garbage is the bundled sound everywhere, including in the label.
    expect(AlertSoundSheet.labelFor(l10n, 'nonsense'), 'ANTA sound');
  });
}

/// Carries the sheet's result out of the closure that awaited it.
class _Holder {
  AlertSoundResult? value;
}

/// A binding that can serve the phone's own sounds, and whose picker is always
/// cancelled — the branch every "what is offered" test needs.
class _PhoneSoundGateway extends NoOpAlertGateway {
  final String? title;

  const _PhoneSoundGateway({this.title});

  @override
  bool get supportsSystemSounds => true;

  @override
  Future<String?> soundTitle(String value) async => title;

  @override
  Future<PickedAlertSound?> pickSystemSound(String? current) async => null;
}

/// A phone with no ringtone picker activity at all.
class _NoPickerGateway extends _PhoneSoundGateway {
  const _NoPickerGateway();

  @override
  Future<PickedAlertSound?> pickSystemSound(String? current) async {
    throw const AlertSoundPickerUnavailable();
  }
}
