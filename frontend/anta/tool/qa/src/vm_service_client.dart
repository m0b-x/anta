import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'agent_protocol.dart';
import 'errors.dart';
import 'poll.dart';

Uri vmServiceWebSocketUri(String raw) {
  final text = raw.trim();
  if (text.isEmpty) throw UsageFailure('empty VM service URI');
  final uri = Uri.parse(text);
  final scheme = switch (uri.scheme) {
    'http' => 'ws',
    'https' => 'wss',
    'ws' || 'wss' => uri.scheme,
    _ => throw UsageFailure('not a VM service URI: $raw'),
  };
  var path = uri.path;
  if (path.endsWith('/ws')) path = path.substring(0, path.length - 2);
  if (!path.endsWith('/')) path = '$path/';
  return uri.replace(scheme: scheme, path: '${path}ws');
}

String vmServiceHttpUri(String host, int port) => 'http://$host:$port/';

Future<int> pickFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

class VmServiceClient {
  VmServiceClient._(this._socket, this.uri) {
    _socket.listen(_onMessage, onError: _onClosed, onDone: _onClosed);
  }

  static Future<VmServiceClient> connect(
    String rawUri, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final uri = vmServiceWebSocketUri(rawUri);
    try {
      final socket = await WebSocket.connect(uri.toString()).timeout(timeout);
      return VmServiceClient._(socket, uri);
    } on TimeoutException {
      throw DeviceFailure(
        'the VM service at $uri did not answer in ${timeout.inSeconds}s',
      );
    } on SocketException catch (e) {
      throw DeviceFailure(
        'cannot reach the VM service at $uri: ${e.osError?.message ?? e.message}',
      );
    } on WebSocketException catch (e) {
      throw DeviceFailure('the VM service at $uri refused the socket: ${e.message}');
    } on IOException catch (e) {
      throw DeviceFailure('the VM service at $uri is not answering yet: $e');
    }
  }

  final WebSocket _socket;
  final Uri uri;
  int _nextId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  String? _driverIsolate;
  bool _closed = false;

  /// How long to keep looking for the driver extension before deciding the
  /// app is not a driver build. Zero for an app that has been up a while (one
  /// look is right and keeps a non-driver app from stalling every verb); a
  /// launch sets seconds, because `main` registers the extension after the
  /// VM service already answers.
  Duration driverWait = Duration.zero;

  bool get isClosed => _closed;

  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, Object?> params = const {},
    Duration timeout = const Duration(seconds: 30),
  ]) async {
    if (_closed) throw DeviceFailure('the VM service connection is closed');
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _socket.add(jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    }));
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(id);
      throw DeviceFailure(
        'VM service call $method timed out after ${timeout.inSeconds}s',
      );
    }
  }

  void _onMessage(dynamic data) {
    final Object? decoded;
    try {
      decoded = jsonDecode(data as String);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    final id = decoded['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    final error = decoded['error'];
    if (error is Map) {
      final detail = error['data'];
      completer.completeError(DeviceFailure(
        'VM service error ${error['code']}: ${error['message']}'
        '${detail == null ? '' : ' $detail'}',
      ));
      return;
    }
    final result = decoded['result'];
    completer.complete(
      result is Map<String, dynamic> ? result : <String, dynamic>{},
    );
  }

  void _onClosed([Object? error, StackTrace? stackTrace]) {
    _closed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          DeviceFailure('the VM service connection closed (app gone?)'),
        );
      }
    }
    _pending.clear();
  }

  Future<String?> _findDriverIsolate() async {
    final vm = await call('getVM');
    final isolates = (vm['isolates'] as List?) ?? const [];
    for (final ref in isolates) {
      if (ref is! Map) continue;
      final id = ref['id'];
      if (id is! String) continue;
      final isolate = await call('getIsolate', {'isolateId': id});
      final rpcs = isolate['extensionRPCs'];
      if (rpcs is List && rpcs.contains(driverExtensionMethod)) return id;
    }
    return null;
  }

  /// The isolate that registered the driver extension, polling for up to
  /// [waitFor]: right after a launch the VM service answers before `main`
  /// has run `enableFlutterDriverExtension`, so a single look would call a
  /// perfectly good driver build "not the driver build".
  Future<String> driverIsolateId({Duration? waitFor}) async {
    final cached = _driverIsolate;
    if (cached != null) return cached;
    final wait = waitFor ?? driverWait;
    final found = await pollUntil<String>(
      timeout: wait,
      interval: const Duration(milliseconds: 200),
      probe: _findDriverIsolate,
    );
    if (found != null) return _driverIsolate = found;
    throw DeviceFailure(
      'no isolate exposes $driverExtensionMethod'
      '${wait > Duration.zero ? ' after ${wait.inSeconds}s' : ''} — the running '
      'app is not the driver build; start it with `qa run` or `qa relaunch`',
    );
  }

  Future<Map<String, dynamic>> driverCommand(
    Map<String, String> params, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final isolate = await driverIsolateId();
    final result = await call(
      driverExtensionMethod,
      {'isolateId': isolate, ...params},
      timeout,
    );
    if (result['isError'] == true) {
      throw DeviceFailure('driver: ${result['response']}');
    }
    return result;
  }

  Future<String> requestData(
    String message, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final result = await driverCommand(
      {'command': 'request_data', 'message': message},
      timeout: timeout,
    );
    final response = result['response'];
    if (response is Map) return '${response['message'] ?? ''}';
    return '$response';
  }

  Future<void> close() async {
    _closed = true;
    await _socket.close().timeout(
      const Duration(seconds: 1),
      onTimeout: () {},
    );
  }
}

Future<VmServiceClient> waitForVmService(
  String rawUri, {
  Duration timeout = const Duration(seconds: 30),
  Duration interval = const Duration(milliseconds: 250),
  Future<bool> Function()? stillWorthWaiting,
}) async {
  DeviceFailure? last;
  final client = await pollUntil<VmServiceClient>(
    timeout: timeout,
    interval: interval,
    probe: () async {
      try {
        final candidate = await VmServiceClient.connect(
          rawUri,
          timeout: const Duration(seconds: 2),
        );
        try {
          await candidate.call('getVM', const {}, const Duration(seconds: 5));
          return candidate;
        } on DeviceFailure catch (e) {
          last = e;
          await candidate.close();
        }
      } on DeviceFailure catch (e) {
        last = e;
      }
      if (stillWorthWaiting != null && !await stillWorthWaiting()) {
        throw DeviceFailure(
          'the app exited before its VM service came up (${last?.message})',
        );
      }
      return null;
    },
  );
  if (client != null) return client;
  throw DeviceFailure(
    'the VM service at $rawUri did not come up within ${timeout.inSeconds}s '
    '(${last?.message ?? 'no answer'})',
  );
}
