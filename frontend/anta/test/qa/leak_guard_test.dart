import 'package:anta/services/sync_availability.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/agent_client.dart';
import '../../tool/qa/src/agent_protocol.dart';
import '../../tool/qa/src/doctor.dart';
import '../../tool/qa/src/log_parse.dart';
import '../../tool/qa/src/runner.dart';

void main() {
  group('SyncAvailability.resolve', () {
    test('a phone build can sync, desktop and web cannot', () {
      expect(
        SyncAvailability.resolve(web: false, phone: true, qaBuild: false, qaAllowsCloud: false),
        isTrue,
      );
      expect(
        SyncAvailability.resolve(web: false, phone: false, qaBuild: false, qaAllowsCloud: false),
        isFalse,
      );
      expect(
        SyncAvailability.resolve(web: true, phone: false, qaBuild: false, qaAllowsCloud: true),
        isFalse,
      );
    });

    test('a QA build is cut off from the cloud unless it opts in', () {
      expect(
        SyncAvailability.resolve(web: false, phone: true, qaBuild: true, qaAllowsCloud: false),
        isFalse,
      );
      expect(
        SyncAvailability.resolve(web: false, phone: true, qaBuild: true, qaAllowsCloud: true),
        isTrue,
      );
    });

    test('this test binary is not a QA build, so the live gate is the platform rule', () {
      expect(SyncAvailability.isSupported, isFalse);
    });
  });

  group('redactSecrets', () {
    final apiKey = ['AI', 'za', 'SyD-', 'FAKE' * 8, '0'].join();
    final oauth = ['1234', '56789012', '-', 'abcdefghijklmnop', 'qrstuvwxyz012345',
        '.apps.google', 'usercontent.com'].join();
    final appId = ['1:', '123456789012', ':android:', '0123456789abcdef'].join();
    final token = ['ya', '29.', 'a0AfH6SMBfakefakefake'].join();
    final jwt = ['ey', 'JhbGciOiJSUzI1NiJ9', '.', 'ey', 'JzdWIiOiIxMjM0NTY3ODkwIn0', '.',
        'c2lnbmF0dXJlLWZha2U'].join();
    final pem = ['-----BEGIN ', 'PRIVATE KEY-----\nMIIEvQIBADANBgkq\n-----END ',
        'PRIVATE KEY-----'].join();

    test('masks a Firebase API key wherever it appears in a line', () {
      final out = redactSecrets('I/flutter: init failed for key=$apiKey (invalid)');
      expect(out, isNot(contains('FAKEFAKE')));
      expect(out, contains('[redacted-api-key]'));
      expect(out, contains('init failed'));
    });

    test('masks OAuth client ids, Firebase app ids, tokens and JWTs', () {
      final out = redactSecrets('client=$oauth app=$appId token=$token jwt=$jwt');
      expect(out, isNot(contains('abcdefghijklmnop')));
      expect(out, contains('[redacted-oauth-client].apps.googleusercontent.com'));
      expect(out, contains('[redacted-firebase-app-id]'));
      expect(out, contains('[redacted-oauth-token]'));
      expect(out, contains('[redacted-jwt]'));
    });

    test('masks authorization headers case-insensitively, and private keys', () {
      final header = ['Authorization: ', 'Bearer ', 'abcdefghijklmnop', '0123456789'].join();
      expect(redactSecrets(header), isNot(contains('0123456789')));
      expect(redactSecrets(pem), '[redacted-private-key]');
    });

    test('masks e-mail addresses, which is what an account screen would log', () {
      expect(redactSecrets('signed in as someone@example.com'),
          'signed in as [redacted-email]');
    });

    test('leaves ordinary log lines, local VM URIs and [qa] lines alone', () {
      const lines = '[qa] seed: imported 4 folders, 3 notes\n'
          'The Dart VM service is listening on http://127.0.0.1:51234/PqG-wGLJQB4=/\n'
          'E/flutter: Unhandled Exception: RangeError (index): 5';
      expect(redactSecrets(lines), lines);
    });

    test('a quoted log tail is redacted before it reaches a failure message', () {
      final tail = tailLines('Gradle said key=$apiKey\nBUILD FAILED', lines: 5);
      expect(tail, isNot(contains('FAKEFAKE')));
      expect(tail, contains('BUILD FAILED'));
    });
  });

  group('cloud isolation is visible to the driver', () {
    Map<String, dynamic> info({Object? cloud}) => {
          AgentKeys.platform: 'android',
          AgentKeys.dpr: 2.625,
          AgentKeys.width: 1080,
          AgentKeys.height: 2400,
          AgentKeys.qaMode: true,
          AgentKeys.database: 'qa',
          AgentKeys.cloud: ?cloud,
        };

    test('describe says whether the build can reach Firebase', () {
      expect(AgentInfo.fromJson(info(cloud: false)).describe(), contains('cloud=off'));
      expect(AgentInfo.fromJson(info(cloud: true)).describe(), contains('cloud=ON'));
      expect(AgentInfo.fromJson(info()).describe(), contains('cloud=?'));
    });

    test('doctor warns about a QA build that opted into the cloud', () {
      final warned = checkAgent(
        vmUri: 'http://127.0.0.1:1/',
        failure: null,
        roundTripMs: 3,
        summary: 'android cloud=ON',
        qaMode: true,
        cloud: true,
      );
      expect(warned.status, CheckStatus.warn);
      expect(warned.fix, contains('ANTA_QA_CLOUD'));
      final isolated = checkAgent(
        vmUri: 'http://127.0.0.1:1/',
        failure: null,
        roundTripMs: 3,
        summary: 'android cloud=off',
        qaMode: true,
        cloud: false,
      );
      expect(isolated.status, CheckStatus.ok);
    });
  });
}
