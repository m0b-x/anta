import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/app_permission.dart';
import 'package:anta/pages/permissions_page.dart';
import 'package:anta/services/permission_gateway.dart';
import 'package:anta/services/permission_service.dart';
import 'package:anta/widgets/permission_tile.dart';

import '../goldens/support/golden_fonts.dart';
import '../services/permission_support.dart';
import 'support/layout_errors.dart';

void main() {
  final notificationsRow = SemanticsIds.permissionTile(
    AppPermission.notifications.name,
  );

  Future<void> pumpPage(WidgetTester tester, PermissionService service) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: PermissionsPage.forTesting(service: service),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a platform with nothing to grant says so', (tester) async {
    await pumpPage(
      tester,
      PermissionService(
        gateway: const NoOpPermissionGateway(),
        store: MemoryPermissionPromptStore(),
        deviceId: () async => 'device-a',
      ),
    );

    expect(find.text('Nothing to allow'), findsOneWidget);
    expect(find.text('Check at launch'), findsNothing);
  });

  testWidgets(
    'a missing essential permission is the headline, and can be asked for',
    (tester) async {
      final gateway = FakePermissionGateway(
        statuses: {
          AppPermission.notifications: PermissionStatus.denied,
          AppPermission.fullScreenIntent: PermissionStatus.granted,
          AppPermission.batteryOptimization: PermissionStatus.denied,
        },
      );
      await pumpPage(tester, permissionServiceOver(gateway));

      expect(find.text("Alarms and reminders can't work yet"), findsOneWidget);
      expect(find.text('1 permission is off'), findsOneWidget);
      // Section headers draw the browser's uppercase label.
      expect(find.text('ESSENTIAL'), findsOneWidget);
      expect(find.text('RECOMMENDED'), findsOneWidget);
      expect(find.text('Alarms & reminders'), findsNothing);
      expect(find.text('On'), findsOneWidget);

      await tester.tap(find.bySemanticsIdentifier(notificationsRow));
      await tester.pumpAndSettle();

      expect(gateway.prompts, [AppPermission.notifications]);
      expect(find.text('Essentials are allowed'), findsOneWidget);
      expect(find.text('On'), findsNWidgets(2));

      await tester.tap(
        find.bySemanticsIdentifier(
          SemanticsIds.permissionTile(AppPermission.batteryOptimization.name),
        ),
      );
      await tester.pumpAndSettle();

      expect(gateway.settingsOpens, [AppPermission.batteryOptimization]);
    },
  );

  testWidgets('everything held reads as all set', (tester) async {
    await pumpPage(
      tester,
      permissionServiceOver(FakePermissionGateway(statuses: allGranted)),
    );

    expect(find.text('All set'), findsOneWidget);
    expect(find.text('Turn on'), findsNothing);
    expect(find.text('Open settings'), findsNothing);
  });

  testWidgets(
    'a prompt the system blocks turns the action into a settings link',
    (tester) async {
      final gateway =
          FakePermissionGateway(
              statuses: {AppPermission.notifications: PermissionStatus.denied},
            )
            ..promptResults[AppPermission.notifications] =
                PermissionPromptResult.blocked;
      await pumpPage(tester, permissionServiceOver(gateway));

      await tester.tap(find.bySemanticsIdentifier(notificationsRow));
      await tester.pumpAndSettle();

      expect(gateway.settingsOpens, [AppPermission.notifications]);
      expect(find.text('Turn on'), findsNothing);
      // Still the essential that blocks alarms: its step reads in the error
      // colour, as its glyph does.
      final colorScheme = Theme.of(
        tester.element(find.text('Open settings')),
      ).colorScheme;
      expect(
        tester.widget<Text>(find.text('Open settings')).style!.color,
        colorScheme.error,
      );
    },
  );

  testWidgets('a status the system could not give is not called all set', (
    tester,
  ) async {
    await pumpPage(
      tester,
      permissionServiceOver(
        FakePermissionGateway(
          statuses: {AppPermission.notifications: PermissionStatus.unknown},
        ),
      ),
    );

    expect(find.text("Couldn't check permissions"), findsOneWidget);
    expect(find.text('All set'), findsNothing);
    expect(find.text('Open settings'), findsOneWidget);
  });

  testWidgets('settings that cannot open say so', (tester) async {
    final gateway = FakePermissionGateway(
      statuses: {AppPermission.fullScreenIntent: PermissionStatus.denied},
    )..settingsAvailable = false;
    await pumpPage(tester, permissionServiceOver(gateway));

    await tester.tap(find.text('Open settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("Couldn't open the system settings"), findsOneWidget);
  });

  testWidgets('a launch check stored off opens off', (tester) async {
    final store = MemoryPermissionPromptStore()..launchPromptEnabled = false;
    await pumpPage(
      tester,
      permissionServiceOver(
        FakePermissionGateway(statuses: allGranted),
        store: store,
      ),
    );

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('the launch check switch is persisted', (tester) async {
    final store = MemoryPermissionPromptStore();
    await pumpPage(
      tester,
      permissionServiceOver(
        FakePermissionGateway(statuses: allGranted),
        store: store,
      ),
    );

    await tester.ensureVisible(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(store.launchPromptEnabled, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('system settings opens the app page', (tester) async {
    final gateway = FakePermissionGateway(statuses: allGranted);
    await pumpPage(tester, permissionServiceOver(gateway));

    await tester.ensureVisible(find.text('System settings'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.permissionsSystemSettings),
    );
    await tester.pumpAndSettle();

    expect(gateway.appSettingsOpens, 1);
  });

  testWidgets('every row a flow reaches carries its id', (tester) async {
    await pumpPage(
      tester,
      permissionServiceOver(FakePermissionGateway(statuses: allGranted)),
    );

    expect(find.bySemanticsIdentifier(SemanticsIds.permissionsList), findsOne);
    for (final permission in allGranted.keys) {
      await tester.scrollUntilVisible(
        find.bySemanticsIdentifier(
          SemanticsIds.permissionTile(permission.name),
        ),
        200,
      );
      expect(
        find.bySemanticsIdentifier(
          SemanticsIds.permissionTile(permission.name),
        ),
        findsOneWidget,
      );
    }
    for (final id in [
      SemanticsIds.permissionsLaunchCheck,
      SemanticsIds.permissionsSystemSettings,
    ]) {
      await tester.scrollUntilVisible(find.bySemanticsIdentifier(id), 200);
      expect(find.bySemanticsIdentifier(id), findsOneWidget);
    }
  });

  testWidgets('while a request runs the other actionable rows wait, disabled '
      'in place; a granted row has no tap at all', (tester) async {
    final gateway = FakePermissionGateway(
      statuses: {
        AppPermission.notifications: PermissionStatus.denied,
        AppPermission.fullScreenIntent: PermissionStatus.granted,
        AppPermission.batteryOptimization: PermissionStatus.denied,
      },
    )..promptGate = Completer<void>();
    await pumpPage(tester, permissionServiceOver(gateway));

    ListTile tileOf(AppPermission permission) => tester.widget<ListTile>(
      find.descendant(
        of: find.bySemanticsIdentifier(
          SemanticsIds.permissionTile(permission.name),
        ),
        matching: find.byType(ListTile),
      ),
    );

    expect(tileOf(AppPermission.fullScreenIntent).onTap, isNull);
    expect(tileOf(AppPermission.fullScreenIntent).enabled, isTrue);
    expect(tileOf(AppPermission.batteryOptimization).enabled, isTrue);

    await tester.tap(find.bySemanticsIdentifier(notificationsRow));
    await tester.pump();

    expect(tileOf(AppPermission.batteryOptimization).enabled, isFalse);
    expect(tileOf(AppPermission.notifications).enabled, isFalse);
    expect(tileOf(AppPermission.fullScreenIntent).enabled, isTrue);

    gateway.promptGate!.complete();
    await tester.pumpAndSettle();

    expect(tileOf(AppPermission.batteryOptimization).enabled, isTrue);
  });

  group('German at 2.0 on 360 × 780', () {
    // Measured with Roboto: the test font's square glyphs are about twice as
    // wide, and would report overflows no device shows.
    setUpAll(loadGoldenFonts);

    // Before S6 the tile's trailing button was laid out first and left the
    // title no width — one letter a line, a row taller than the phone.
    testWidgets('every permission denied, no title is squeezed by its value', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final errors = await layoutErrorsDuring(() async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('de'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
            home: PermissionsPage.forTesting(
              service: permissionServiceOver(
                FakePermissionGateway(
                  statuses: {
                    for (final permission in AppPermission.values)
                      permission: PermissionStatus.denied,
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      });

      expect(errors.map((e) => e.exceptionAsString()), isEmpty);
      expect(tester.takeException(), isNull);
      final de = lookupAppLocalizations(const Locale('de'));
      for (final permission in AppPermission.values) {
        final row = find.bySemanticsIdentifier(
          SemanticsIds.permissionTile(permission.name),
        );
        await tester.scrollUntilVisible(row, 200);
        final title = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: row,
            matching: find.text(
              PermissionPresentation.titleOf(de, permission),
              findRichText: true,
            ),
          ),
        );
        // The title holds its longest word, or — "Benachrichtigungen" at 2.0
        // is wider than the phone's whole text column — the whole column,
        // the value moved under it rather than beside.
        final column =
            tester
                .getSize(
                  find.descendant(of: row, matching: find.byType(ListTile)),
                )
                .width -
            FormMetrics.settingsRowPadding.horizontal -
            FormMetrics.settingsLeadingWidth -
            FormMetrics.settingsTitleGap;
        expect(
          title.size.width + 0.5,
          greaterThanOrEqualTo(
            math.min(title.getMinIntrinsicWidth(double.infinity), column),
          ),
          reason: '${permission.name} is squeezed by its value',
        );
        expect(tester.getSize(row).height, lessThan(780));
      }
    });
  });
}
