import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/app_permission.dart';
import 'package:anta/services/android_alert_gateway.dart';
import 'package:anta/services/android_permission_gateway.dart';

const _pluginChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);
const _appChannel = MethodChannel(AndroidPermissionGateway.channelName);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> appCalls;
  late List<MethodCall> pluginCalls;
  late Object? statusAnswer;
  late List<bool> rationaleAnswers;
  late Object? promptAnswer;
  late Map<String, Object?> openAnswers;

  AndroidPermissionGateway gateway() => AndroidPermissionGateway(
    notificationChannelIds: const [
      kAlertReminderChannelId,
      kAlertAlarmChannelId,
    ],
    notifications: AndroidFlutterLocalNotificationsPlugin(),
  );

  setUp(() {
    appCalls = [];
    pluginCalls = [];
    statusAnswer = <String, bool?>{};
    rationaleAnswers = [];
    promptAnswer = true;
    openAnswers = {};
    messenger.setMockMethodCallHandler(_appChannel, (call) async {
      appCalls.add(call);
      switch (call.method) {
        case 'status':
          final answer = statusAnswer;
          if (answer is Exception) throw answer;
          return answer;
        case 'shouldExplainNotifications':
          return rationaleAnswers.isEmpty
              ? false
              : rationaleAnswers.removeAt(0);
        default:
          final answer = openAnswers[call.method];
          if (answer is Exception) throw answer;
          return answer;
      }
    });
    messenger.setMockMethodCallHandler(_pluginChannel, (call) async {
      pluginCalls.add(call);
      final answer = promptAnswer;
      if (answer is Exception) throw answer;
      return answer;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_appChannel, null);
    messenger.setMockMethodCallHandler(_pluginChannel, null);
  });

  group('statuses', () {
    test('one round trip, carrying the alert channel ids', () async {
      statusAnswer = <String, bool?>{'notifications': true};

      await gateway().statuses();

      expect(appCalls.single.method, 'status');
      expect(appCalls.single.arguments, {
        'channels': [kAlertReminderChannelId, kAlertAlarmChannelId],
      });
    });

    test('true, false, null and absent are four different answers', () async {
      statusAnswer = <String, bool?>{
        'notifications': false,
        'fullScreenIntent': true,
        'batteryOptimization': null,
      };

      final statuses = await gateway().statuses();

      expect(statuses, {
        AppPermission.notifications: PermissionStatus.denied,
        AppPermission.fullScreenIntent: PermissionStatus.granted,
        AppPermission.batteryOptimization: PermissionStatus.unknown,
      });
      expect(statuses.containsKey(AppPermission.exactAlarms), isFalse);
    });

    test(
      'a dead channel reads as unknown, never as nothing to grant',
      () async {
        statusAnswer = PlatformException(code: 'gone');

        final statuses = await gateway().statuses();

        expect(statuses.keys, AppPermission.values);
        expect(
          statuses.values.every((status) => status == PermissionStatus.unknown),
          isTrue,
        );
      },
    );
  });

  group('prompt', () {
    test('only notifications have a system prompt', () {
      final binding = gateway();

      expect(binding.canPrompt(AppPermission.notifications), isTrue);
      for (final permission in AppPermission.values) {
        if (permission == AppPermission.notifications) continue;
        expect(binding.canPrompt(permission), isFalse, reason: permission.name);
      }
    });

    test('a grant is a grant', () async {
      promptAnswer = true;

      expect(
        await gateway().prompt(AppPermission.notifications),
        PermissionPromptResult.granted,
      );
      expect(pluginCalls.single.method, 'requestNotificationsPermission');
    });

    test('a first refusal flips the rationale, so it was answered', () async {
      promptAnswer = false;
      rationaleAnswers = [false, true];

      expect(
        await gateway().prompt(AppPermission.notifications),
        PermissionPromptResult.denied,
      );
    });

    test(
      'a second refusal started from the rationale, so it was answered',
      () async {
        promptAnswer = false;
        rationaleAnswers = [true, false];

        expect(
          await gateway().prompt(AppPermission.notifications),
          PermissionPromptResult.denied,
        );
      },
    );

    test(
      'no rationale before or after means the system showed nothing',
      () async {
        promptAnswer = false;
        rationaleAnswers = [false, false];

        expect(
          await gateway().prompt(AppPermission.notifications),
          PermissionPromptResult.blocked,
        );
      },
    );

    test('a plugin failure is a block, not a refusal', () async {
      promptAnswer = PlatformException(code: 'permissionRequestInProgress');

      expect(
        await gateway().prompt(AppPermission.notifications),
        PermissionPromptResult.blocked,
      );
    });

    test('a permission with no prompt never reaches the plugin', () async {
      expect(
        await gateway().prompt(AppPermission.fullScreenIntent),
        PermissionPromptResult.blocked,
      );
      expect(pluginCalls, isEmpty);
    });
  });

  group('settings', () {
    test('each permission opens its own system page', () async {
      openAnswers = {
        'openNotificationSettings': true,
        'openExactAlarmSettings': true,
        'openFullScreenIntentSettings': true,
        'openAppSettings': true,
      };
      final binding = gateway();

      for (final permission in AppPermission.values) {
        expect(await binding.openSettings(permission), isTrue);
      }
      expect(await binding.openAppSettings(), isTrue);

      expect(appCalls.map((call) => call.method), [
        'openNotificationSettings',
        'openExactAlarmSettings',
        'openFullScreenIntentSettings',
        'openAppSettings',
        'openAppSettings',
      ]);
    });

    test('a page that cannot open answers false', () async {
      openAnswers = {
        'openNotificationSettings': false,
        'openAppSettings': PlatformException(code: 'nope'),
      };
      final binding = gateway();

      expect(await binding.openSettings(AppPermission.notifications), isFalse);
      expect(await binding.openAppSettings(), isFalse);
      expect(
        await binding.openSettings(AppPermission.fullScreenIntent),
        isFalse,
      );
    });
  });
}
