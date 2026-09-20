import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/bloc/permissions/permissions_bloc.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/app_permission.dart';
import 'package:anta/pages/permissions_page.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/permission_service.dart';
import 'package:anta/widgets/permission_prompt_dialog.dart';

import '../services/permission_support.dart';

void main() {
  late PermissionPromptChoice? choice;
  late bool finished;

  setUp(() {
    choice = null;
    finished = false;
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  Future<void> pumpAndOpen(
    WidgetTester tester,
    PermissionService service,
  ) async {
    GetIt.I.registerFactory<PermissionsBloc>(
      () => PermissionsBloc(service: service),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final snapshot = await service.launchPromptSnapshot();
                if (snapshot == null || !context.mounted) {
                  finished = true;
                  return;
                }
                choice = await PermissionLaunchPrompt.show(
                  context,
                  service: service,
                  snapshot: snapshot,
                );
                finished = true;
              },
              child: const Text('launch'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('launch'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists what is missing, essentials and recommended apart', (
    tester,
  ) async {
    final gateway = FakePermissionGateway(
      statuses: {
        AppPermission.notifications: PermissionStatus.denied,
        AppPermission.fullScreenIntent: PermissionStatus.granted,
        AppPermission.batteryOptimization: PermissionStatus.denied,
      },
    );
    await pumpAndOpen(tester, permissionServiceOver(gateway));

    expect(find.text('ANTA needs your permission'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Unrestricted battery'), findsOneWidget);
    expect(
      find.text('Recommended · Battery limits can delay or drop an alarm'),
      findsOneWidget,
    );
    expect(find.text('Full-screen alarms'), findsNothing);
    expect(gateway.prompts, isEmpty);
  });

  testWidgets('nothing essential missing raises no dialog at all', (
    tester,
  ) async {
    await pumpAndOpen(
      tester,
      permissionServiceOver(
        FakePermissionGateway(
          statuses: {
            ...allGranted,
            AppPermission.batteryOptimization: PermissionStatus.denied,
          },
        ),
      ),
    );

    expect(finished, isTrue);
    expect(find.text('ANTA needs your permission'), findsNothing);
  });

  testWidgets('Not now asks nothing, and is remembered', (tester) async {
    final store = MemoryPermissionPromptStore();
    final gateway = FakePermissionGateway(
      statuses: {AppPermission.notifications: PermissionStatus.denied},
    );
    final service = permissionServiceOver(gateway, store: store);
    await pumpAndOpen(tester, service);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(choice, PermissionPromptChoice.notNow);
    expect(gateway.prompts, isEmpty);
    expect(store.acknowledgement, 'device-a|notifications');
    expect(await service.launchPromptSnapshot(), isNull);
  });

  testWidgets('Continue runs the system prompt and confirms when all is held', (
    tester,
  ) async {
    final store = MemoryPermissionPromptStore();
    final gateway = FakePermissionGateway(
      statuses: {
        ...allGranted,
        AppPermission.notifications: PermissionStatus.denied,
      },
    );
    await pumpAndOpen(tester, permissionServiceOver(gateway, store: store));

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(choice, PermissionPromptChoice.done);
    expect(gateway.prompts, [AppPermission.notifications]);
    expect(gateway.settingsOpens, isEmpty);
    expect(store.acknowledgement, 'device-a|');
    expect(find.text('All set'), findsOneWidget);
    expect(find.byType(PermissionsPage), findsNothing);
  });

  testWidgets(
    'Continue lands on the Permissions page while something is left',
    (tester) async {
      final store = MemoryPermissionPromptStore();
      final gateway = FakePermissionGateway(
        statuses: {
          AppPermission.notifications: PermissionStatus.denied,
          AppPermission.batteryOptimization: PermissionStatus.denied,
        },
      );
      await pumpAndOpen(tester, permissionServiceOver(gateway, store: store));

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(choice, PermissionPromptChoice.review);
      expect(gateway.prompts, [AppPermission.notifications]);
      expect(gateway.settingsOpens, isEmpty);
      expect(find.byType(PermissionsPage), findsOneWidget);
      expect(find.text('Essentials are allowed'), findsOneWidget);
    },
  );

  testWidgets('Continue never stacks a second Permissions page on the first', (
    tester,
  ) async {
    final gateway = FakePermissionGateway(
      statuses: {
        AppPermission.notifications: PermissionStatus.denied,
        AppPermission.batteryOptimization: PermissionStatus.denied,
      },
    );
    final service = permissionServiceOver(gateway);
    GetIt.I.registerFactory<PermissionsBloc>(
      () => PermissionsBloc(service: service),
    );
    late BuildContext root;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [AppNavigator.routeObserver],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) {
            root = context;
            return const Scaffold();
          },
        ),
      ),
    );
    AppNavigator.toPermissions(root);
    await tester.pumpAndSettle();
    expect(find.byType(PermissionsPage), findsOneWidget);

    final snapshot = await service.launchPromptSnapshot();
    PermissionLaunchPrompt.show(root, service: service, snapshot: snapshot!);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byType(PermissionsPage, skipOffstage: false), findsOneWidget);
    expect(find.text('Essentials are allowed'), findsOneWidget);
  });

  group('maybeShow', () {
    Future<BuildContext> pumpRoot(WidgetTester tester) async {
      late BuildContext root;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              root = context;
              return const Scaffold();
            },
          ),
        ),
      );
      return root;
    }

    PermissionService missingNotifications() => permissionServiceOver(
      FakePermissionGateway(
        statuses: {AppPermission.notifications: PermissionStatus.denied},
      ),
    );

    testWidgets('raises the dialog when something essential is missing', (
      tester,
    ) async {
      final root = await pumpRoot(tester);

      PermissionLaunchPrompt.maybeShow(
        service: missingNotifications(),
        context: () => root,
        isInterrupted: () => false,
      );
      await tester.pumpAndSettle();

      expect(find.text('ANTA needs your permission'), findsOneWidget);
    });

    testWidgets('stays away while an alert has the screen', (tester) async {
      final root = await pumpRoot(tester);
      final gateway = FakePermissionGateway(
        statuses: {AppPermission.notifications: PermissionStatus.denied},
      );

      final choice = await PermissionLaunchPrompt.maybeShow(
        service: permissionServiceOver(gateway),
        context: () => root,
        isInterrupted: () => true,
      );
      await tester.pumpAndSettle();

      expect(choice, isNull);
      expect(gateway.statusReads, 0);
      expect(find.text('ANTA needs your permission'), findsNothing);
    });

    testWidgets('an alert arriving during the check still wins', (
      tester,
    ) async {
      final root = await pumpRoot(tester);
      var checks = 0;

      final choice = await PermissionLaunchPrompt.maybeShow(
        service: missingNotifications(),
        context: () => root,
        isInterrupted: () => ++checks > 1,
      );
      await tester.pumpAndSettle();

      expect(choice, isNull);
      expect(find.text('ANTA needs your permission'), findsNothing);
    });

    testWidgets('no navigator yet means no dialog, not a crash', (
      tester,
    ) async {
      await pumpRoot(tester);

      final choice = await PermissionLaunchPrompt.maybeShow(
        service: missingNotifications(),
        context: () => null,
        isInterrupted: () => false,
      );

      expect(choice, isNull);
    });
  });

  testWidgets('system back is not an answer, so it is asked again', (
    tester,
  ) async {
    final store = MemoryPermissionPromptStore();
    final service = permissionServiceOver(
      FakePermissionGateway(
        statuses: {AppPermission.notifications: PermissionStatus.denied},
      ),
      store: store,
    );
    await pumpAndOpen(tester, service);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('ANTA needs your permission'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(finished, isTrue);
    expect(choice, isNull);
    expect(store.acknowledgement, isNull);
    expect(await service.launchPromptSnapshot(), isNotNull);
  });
}
