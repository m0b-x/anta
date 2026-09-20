import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/app_permission.dart';
import 'package:anta/pages/permissions_page.dart';
import 'package:anta/services/permission_gateway.dart';
import 'package:anta/services/permission_service.dart';

import '../services/permission_support.dart';

void main() {
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
      expect(find.text('Essential'), findsOneWidget);
      expect(find.text('Recommended'), findsOneWidget);
      expect(find.text('Alarms & reminders'), findsNothing);
      expect(find.text('On'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Turn on'));
      await tester.pumpAndSettle();

      expect(gateway.prompts, [AppPermission.notifications]);
      expect(find.text('Essentials are allowed'), findsOneWidget);
      expect(find.text('On'), findsNWidgets(2));

      await tester.tap(find.widgetWithText(TextButton, 'Open settings'));
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

      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      expect(gateway.settingsOpens, [AppPermission.notifications]);
      expect(find.text('Turn on'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Open settings'),
        findsOneWidget,
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
    await tester.tap(find.text('System settings'));
    await tester.pumpAndSettle();

    expect(gateway.appSettingsOpens, 1);
  });
}
