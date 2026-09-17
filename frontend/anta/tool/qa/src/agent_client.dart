import 'dart:convert';

import 'agent_protocol.dart';
import 'device.dart';
import 'errors.dart';
import 'gestures.dart';
import 'ui_tree.dart';
import 'vm_service_client.dart';

/// What the agent's `info` op reported.
class AgentInfo {
  const AgentInfo({
    required this.platform,
    required this.dpr,
    required this.width,
    required this.height,
    required this.lifecycle,
    required this.semanticsEnabled,
    required this.textClient,
    required this.documentsPath,
    required this.qaMode,
    required this.database,
    required this.qaLog,
    required this.qaOutcomes,
    required this.uptimeMs,
    required this.protocolVersion,
    this.firstFrame = true,
    this.cloud,
  });

  factory AgentInfo.fromJson(Map<String, dynamic> json) => AgentInfo(
        platform: '${json[AgentKeys.platform] ?? '?'}',
        dpr: (json[AgentKeys.dpr] as num? ?? 1).toDouble(),
        width: (json[AgentKeys.width] as num? ?? 0).toInt(),
        height: (json[AgentKeys.height] as num? ?? 0).toInt(),
        lifecycle: json[AgentKeys.lifecycle] as String?,
        semanticsEnabled: json[AgentKeys.semantics] == true,
        textClient: json[AgentKeys.textClient] == true,
        documentsPath: json[AgentKeys.documentsPath] as String?,
        qaMode: json[AgentKeys.qaMode] == true,
        database: json[AgentKeys.database] as String?,
        qaLog: ((json[AgentKeys.qaLog] as List?) ?? const [])
            .map((line) => '$line')
            .toList(),
        qaOutcomes: ((json[AgentKeys.qaOutcomes] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => QaOutcome(
                  kind: '${e['kind'] ?? ''}',
                  ok: e['ok'] == true,
                  message: '${e['message'] ?? ''}',
                ))
            .toList(),
        uptimeMs: (json[AgentKeys.uptimeMs] as num? ?? 0).toInt(),
        protocolVersion: (json[AgentKeys.agentVersion] as num? ?? 0).toInt(),
        firstFrame: json[AgentKeys.firstFrame] != false,
        cloud: json[AgentKeys.cloud] as bool?,
      );

  final String platform;
  final double dpr;
  final int width;
  final int height;
  final String? lifecycle;
  final bool semanticsEnabled;
  final bool textClient;
  final String? documentsPath;
  final bool qaMode;
  final String? database;
  final List<String> qaLog;
  final List<QaOutcome> qaOutcomes;
  final int uptimeMs;
  final int protocolVersion;

  /// False while the app is still starting up: `main` has run far enough to
  /// answer, but nothing is drawn yet.
  final bool firstFrame;

  /// Whether this build can reach Firebase (sign-in, pairing). Null from an
  /// agent that predates the field. A QA build answers false unless it was
  /// built with `ANTA_QA_CLOUD=true`.
  final bool? cloud;

  ScreenSize get screen => ScreenSize(
        physicalWidth: width,
        physicalHeight: height,
        density: (dpr * 160).round(),
      );

  /// The `[qa]` lines as they would read in a log, so the same parser works.
  String get qaLogText => qaLog.map((line) => '[qa] $line').join('\n');

  String describe() =>
      '$platform  ${width}x$height @${dpr}x  lifecycle=${lifecycle ?? '?'}  '
      'semantics=${semanticsEnabled ? 'on' : 'off'}  '
      'textField=${textClient ? 'focused' : 'none'}  '
      'qa=${qaMode ? (database ?? 'qa') : 'OFF (owner database!)'}  '
      'cloud=${cloud == null ? '?' : (cloud! ? 'ON' : 'off')}';
}

/// One typed `[qa]` outcome, as `QaBootstrap.entries` records it.
class QaOutcome {
  const QaOutcome({required this.kind, required this.ok, required this.message});

  final String kind;
  final bool ok;
  final String message;
}

/// Typed client for the in-app agent, reached through the Driver extension's
/// `request_data` command over the VM service.
class AgentClient implements UiDriver {
  AgentClient(this.vm, {required this.appPackage});

  final VmServiceClient vm;
  final String appPackage;
  AgentInfo? _info;

  @override
  String get name => 'agent';

  @override
  Duration get pollInterval => const Duration(milliseconds: 120);

  @override
  Duration get settleAfterAction => Duration.zero;

  String _lastRaw = '';

  Future<Map<String, dynamic>> op(
    String op, [
    Map<String, Object?> args = const {},
    Duration timeout = const Duration(seconds: 30),
  ]) async {
    final raw = await vm.requestData(
      jsonEncode({AgentKeys.op: op, ...args}),
      timeout: timeout,
    );
    _lastRaw = raw;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw DeviceFailure('the agent answered $op with something other than '
          'JSON: ${raw.length > 200 ? '${raw.substring(0, 200)}…' : raw}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw DeviceFailure('the agent answered $op with $decoded');
    }
    if (decoded[AgentKeys.ok] != true) {
      final message = '${decoded[AgentKeys.error] ?? 'unknown agent error'}';
      switch (decoded[AgentKeys.errorKind]) {
        case AgentErrorKinds.target:
          throw TargetFailure(message);
        case AgentErrorKinds.usage:
          throw UsageFailure(message);
        default:
          final stack = decoded[AgentKeys.stack];
          throw DeviceFailure(
            'agent $op: $message'
            '${stack == null ? '' : '\n${_clip('$stack', 12)}'}',
          );
      }
    }
    return decoded;
  }

  static String _clip(String text, int lines) {
    final all = text.trimRight().split('\n');
    if (all.length <= lines) return text;
    return '${all.take(lines).join('\n')}\n  … ${all.length - lines} more';
  }

  Future<AgentInfo> info({bool refresh = false}) async {
    final cached = _info;
    if (cached != null && !refresh) return cached;
    return _info = AgentInfo.fromJson(
      await op(AgentOps.info, const {}, const Duration(seconds: 10)),
    );
  }

  @override
  Future<ScreenSize> screenSize() async => (await info()).screen;

  @override
  Future<UiDump> dump() async {
    final decoded = await op(AgentOps.dump);
    return UiDump(
      raw: _lastRaw,
      tree: UiTree.fromAgentMap(decoded, appPackage: appPackage),
    );
  }

  @override
  Future<void> tap(int x, int y) async {
    await op(AgentOps.tap, {AgentKeys.x: x, AgentKeys.y: y});
  }

  @override
  Future<void> longPress(int x, int y, int ms) async {
    await op(AgentOps.longPress, {AgentKeys.x: x, AgentKeys.y: y, AgentKeys.ms: ms});
  }

  @override
  Future<void> swipePath(SwipePath path) async {
    await op(AgentOps.swipe, {
      AgentKeys.x: path.x1,
      AgentKeys.y: path.y1,
      AgentKeys.x2: path.x2,
      AgentKeys.y2: path.y2,
      AgentKeys.ms: path.durationMs,
    });
  }

  @override
  Future<void> clear() => typeText('', replace: true);

  @override
  Future<void> drag(
    int x1,
    int y1,
    int x2,
    int y2, {
    required int holdMs,
    required int moveMs,
  }) async {
    await op(AgentOps.drag, {
      AgentKeys.x: x1,
      AgentKeys.y: y1,
      AgentKeys.x2: x2,
      AgentKeys.y2: y2,
      AgentKeys.holdMs: holdMs,
      AgentKeys.ms: moveMs,
    }, const Duration(seconds: 60));
  }

  @override
  @override
  Future<TypeOutcome> typeText(String text, {bool replace = false}) async {
    final result = await op(AgentOps.type, {
      AgentKeys.text: text,
      AgentKeys.replace: replace,
    });
    return TypeOutcome(
      imeShown: true,
      text: result[AgentKeys.text] as String?,
      selection: (result[AgentKeys.selection] as num?)?.toInt(),
    );
  }

  @override
  Future<String> key(String name) async {
    final result = await op(AgentOps.key, {AgentKeys.name: name});
    final action = result['action'];
    final sent = '${result[AgentKeys.name] ?? name}';
    if (result[AgentKeys.popped] == false) {
      return '$sent (nothing to pop — already at the root route, so the app '
          'was left running)';
    }
    return action == null ? sent : '$sent (text action $action)';
  }

  Future<List<int>> screenshotPng() async {
    final result = await op(AgentOps.screenshot, const {}, const Duration(seconds: 60));
    final png = result[AgentKeys.png];
    if (png is! String || png.isEmpty) {
      throw DeviceFailure('the agent returned no screenshot');
    }
    return base64Decode(png);
  }

  Future<List<String>> errors({bool clear = false}) async {
    final result = await op(AgentOps.errors, {AgentKeys.clear: clear});
    return ((result[AgentKeys.list] as List?) ?? const [])
        .map((line) => '$line')
        .toList();
  }

  Future<void> settle({int ms = 500}) async {
    await op(AgentOps.settle, {AgentKeys.ms: ms});
  }

  Future<void> close() => vm.close();
}
