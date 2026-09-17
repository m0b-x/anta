import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/agent_client.dart';
import '../../tool/qa/src/agent_protocol.dart';
import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/vm_service_client.dart';

/// A stand-in VM service: answers `getVM`, `getIsolate` and the driver
/// extension the way the real one does, so the client's framing and isolate
/// discovery are exercised end to end over a real WebSocket.
class _FakeVmService {
  _FakeVmService(this.server) {
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((data) => _handle(socket, jsonDecode(data as String) as Map));
    });
  }

  static Future<_FakeVmService> start() async =>
      _FakeVmService(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer server;
  final List<WebSocket> sockets = [];
  final List<Map<String, dynamic>> requests = [];
  final Map<String, String> agentReplies = {};

  String get httpUri => 'http://127.0.0.1:${server.port}/token=/';

  void _handle(WebSocket socket, Map request) {
    requests.add(Map<String, dynamic>.from(request));
    final id = request['id'];
    final method = request['method'];
    final params = (request['params'] as Map?) ?? const {};
    Object? result;
    Map<String, Object?>? error;
    switch (method) {
      case 'getVM':
        result = {
          'type': 'VM',
          'isolates': [
            {'id': 'isolates/drift', 'name': 'Drift isolate worker'},
            {'id': 'isolates/main', 'name': 'main'},
          ],
        };
      case 'getIsolate':
        result = params['isolateId'] == 'isolates/main'
            ? {'extensionRPCs': ['ext.flutter.inspector.show', driverExtensionMethod]}
            : {'type': 'Sentinel', 'kind': 'Collected'};
      case driverExtensionMethod:
        final message = params['message'] as String? ?? '';
        final op = (jsonDecode(message) as Map)[AgentKeys.op];
        result = {
          'isError': false,
          'response': {
            'message': agentReplies[op] ??
                jsonEncode({AgentKeys.ok: false, AgentKeys.error: 'no script for $op'}),
          },
        };
      default:
        error = {'code': -32601, 'message': 'Method not found', 'data': {'method': method}};
    }
    socket.add(jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      if (error != null) 'error': error else 'result': result,
    }));
  }

  Future<void> close() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
  }
}

void main() {
  group('vmServiceWebSocketUri', () {
    test('turns the printed http URI into the ws endpoint', () {
      expect(
        vmServiceWebSocketUri('http://127.0.0.1:61234/abc=/').toString(),
        'ws://127.0.0.1:61234/abc=/ws',
      );
      expect(
        vmServiceWebSocketUri('http://127.0.0.1:54321/').toString(),
        'ws://127.0.0.1:54321/ws',
      );
    });

    test('leaves a ws URI alone and adds a missing /ws', () {
      expect(
        vmServiceWebSocketUri('ws://127.0.0.1:1/x=/ws').toString(),
        'ws://127.0.0.1:1/x=/ws',
      );
      expect(
        vmServiceWebSocketUri('ws://127.0.0.1:1/x=').toString(),
        'ws://127.0.0.1:1/x=/ws',
      );
    });

    test('rejects anything that is not a service URI', () {
      expect(() => vmServiceWebSocketUri(''), throwsA(isA<UsageFailure>()));
      expect(() => vmServiceWebSocketUri('ftp://x'), throwsA(isA<UsageFailure>()));
    });
  });

  test('vmServiceHttpUri is the shape the engine serves without auth codes', () {
    expect(vmServiceHttpUri('127.0.0.1', 5000), 'http://127.0.0.1:5000/');
  });

  test('pickFreePort returns a bindable loopback port', () async {
    final port = await pickFreePort();
    expect(port, greaterThan(0));
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await socket.close();
  });

  group('VmServiceClient against a fake service', () {
    late _FakeVmService service;

    setUp(() async {
      service = await _FakeVmService.start();
    });

    tearDown(() => service.close());

    test('finds the isolate that exposes the driver extension', () async {
      final client = await VmServiceClient.connect(service.httpUri);
      expect(await client.driverIsolateId(), 'isolates/main');
      expect(await client.driverIsolateId(), 'isolates/main');
      final isolateLookups =
          service.requests.where((r) => r['method'] == 'getIsolate').length;
      expect(isolateLookups, 2, reason: 'the id is cached after the first walk');
      await client.close();
    });

    test('request_data carries the message to the extension and back', () async {
      service.agentReplies[AgentOps.info] = jsonEncode({
        AgentKeys.ok: true,
        AgentKeys.platform: 'iOS',
        AgentKeys.dpr: 3.0,
        AgentKeys.width: 1320,
        AgentKeys.height: 2868,
        AgentKeys.lifecycle: 'resumed',
        AgentKeys.semantics: true,
        AgentKeys.qaMode: true,
        AgentKeys.database: 'qa',
        AgentKeys.qaLog: ['reset: cleared preferences and qa.db'],
      });
      final client = await VmServiceClient.connect(service.httpUri);
      final agent = AgentClient(client, appPackage: 'com.alexzamfir.anta');
      final info = await agent.info();
      expect(info.platform, 'iOS');
      expect(info.screen.width, 1320);
      expect(info.screen.density, 480);
      expect(info.qaLogText, '[qa] reset: cleared preferences and qa.db');
      expect(info.describe(), contains('lifecycle=resumed'));
      final driverCall = service.requests.lastWhere(
        (r) => r['method'] == driverExtensionMethod,
      );
      expect((driverCall['params'] as Map)['command'], 'request_data');
      expect((driverCall['params'] as Map)['isolateId'], 'isolates/main');
      await client.close();
    });

    test('an agent error becomes the matching QaException', () async {
      service.agentReplies[AgentOps.type] = jsonEncode({
        AgentKeys.ok: false,
        AgentKeys.error: 'no text field is focused',
        AgentKeys.errorKind: AgentErrorKinds.target,
      });
      service.agentReplies[AgentOps.key] = jsonEncode({
        AgentKeys.ok: false,
        AgentKeys.error: 'unknown key',
        AgentKeys.errorKind: AgentErrorKinds.usage,
      });
      service.agentReplies[AgentOps.tap] = jsonEncode({
        AgentKeys.ok: false,
        AgentKeys.error: 'boom',
        AgentKeys.stack: 'frame 1\nframe 2',
      });
      final client = await VmServiceClient.connect(service.httpUri);
      final agent = AgentClient(client, appPackage: 'x');
      await expectLater(() => agent.typeText('a'), throwsA(isA<TargetFailure>()));
      await expectLater(() => agent.key('zz'), throwsA(isA<UsageFailure>()));
      await expectLater(
        () => agent.tap(1, 1),
        throwsA(isA<DeviceFailure>()
            .having((e) => e.message, 'message', contains('frame 1'))),
      );
      await client.close();
    });

    test('a JSON-RPC error surfaces as a device failure', () async {
      final client = await VmServiceClient.connect(service.httpUri);
      await expectLater(
        () => client.call('noSuchMethod'),
        throwsA(isA<DeviceFailure>()
            .having((e) => e.message, 'message', contains('Method not found'))),
      );
      await client.close();
    });

    test('connecting to a closed port fails fast with the address', () async {
      final port = await pickFreePort();
      await expectLater(
        () => VmServiceClient.connect('http://127.0.0.1:$port/'),
        throwsA(isA<DeviceFailure>()
            .having((e) => e.message, 'message', contains('$port'))),
      );
    });

    test('waitForVmService gives up when the app is reported gone', () async {
      final port = await pickFreePort();
      await expectLater(
        () => waitForVmService(
          'http://127.0.0.1:$port/',
          timeout: const Duration(seconds: 5),
          interval: const Duration(milliseconds: 10),
          stillWorthWaiting: () async => false,
        ),
        throwsA(isA<DeviceFailure>()
            .having((e) => e.message, 'message', contains('exited'))),
      );
    });

    test('a port that accepts and hangs up reads as not ready, never as a crash', () async {
      final forwarder = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      forwarder.listen((socket) => socket.destroy());
      addTearDown(forwarder.close);
      await expectLater(
        () => VmServiceClient.connect('http://127.0.0.1:${forwarder.port}/'),
        throwsA(isA<DeviceFailure>()),
      );
    });

    test('waitForVmService returns a client once the service answers', () async {
      final client = await waitForVmService(
        service.httpUri,
        timeout: const Duration(seconds: 5),
      );
      expect(await client.driverIsolateId(), 'isolates/main');
      await client.close();
    });
  });
}
