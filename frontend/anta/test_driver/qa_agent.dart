import 'dart:async';
import 'dart:convert';
import 'dart:io' show ProcessInfo;
import 'dart:ui' as ui;

import 'package:anta/core/qa/qa_bootstrap.dart';
import 'package:anta/core/qa/qa_mode.dart';
import 'package:anta/services/sync_availability.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

import '../tool/qa/src/agent_protocol.dart';

class QaAgentException implements Exception {
  QaAgentException(this.message, {this.kind = AgentErrorKinds.device});

  final String message;
  final String kind;

  @override
  String toString() => message;
}

class QaAgent {
  QaAgent();

  final TestTextInput _textInput = TestTextInput();
  final List<String> _errors = <String>[];
  final List<ui.FrameTiming> _timings = <ui.FrameTiming>[];
  final DateTime _startedAt = DateTime.now();
  SemanticsHandle? _semantics;
  LiveWidgetController? _controllerCache;
  bool _hooksInstalled = false;
  bool _recordingFrames = false;
  DateTime? _recordingSince;

  static const int _errorLimit = 100;
  static const Duration _settleCap = Duration(milliseconds: 500);
  static const Duration _frameCap = Duration(milliseconds: 400);

  static const Map<String, LogicalKeyboardKey> _logicalKeys = {
    'enter': LogicalKeyboardKey.enter,
    'tab': LogicalKeyboardKey.tab,
    'escape': LogicalKeyboardKey.escape,
    'backspace': LogicalKeyboardKey.backspace,
    'arrowUp': LogicalKeyboardKey.arrowUp,
    'arrowDown': LogicalKeyboardKey.arrowDown,
    'arrowLeft': LogicalKeyboardKey.arrowLeft,
    'arrowRight': LogicalKeyboardKey.arrowRight,
    'pageUp': LogicalKeyboardKey.pageUp,
    'pageDown': LogicalKeyboardKey.pageDown,
    'space': LogicalKeyboardKey.space,
  };

  void install() {
    _textInput.register();
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) => _installErrorHooks());
  }

  void _onFrameTimings(List<ui.FrameTiming> timings) {
    if (!_recordingFrames) return;
    _timings.addAll(timings);
    if (_timings.length > 20000) _timings.removeRange(0, _timings.length - 20000);
  }

  LiveWidgetController get _controller =>
      _controllerCache ??= LiveWidgetController(WidgetsBinding.instance);

  Future<String> handle(String? message) async {
    final Map<String, dynamic> request;
    try {
      final decoded = message == null || message.isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(message);
      if (decoded is! Map<String, dynamic>) {
        return _fail('a request must be a JSON object', AgentErrorKinds.usage);
      }
      request = decoded;
    } on FormatException catch (e) {
      return _fail('bad request JSON: ${e.message}', AgentErrorKinds.usage);
    }
    final op = request[AgentKeys.op] as String? ?? '';
    try {
      final result = await _dispatch(op, request);
      return jsonEncode(<String, Object?>{AgentKeys.ok: true, ...result});
    } on QaAgentException catch (e) {
      return _fail(e.message, e.kind);
    } catch (e, stack) {
      return _fail('$op failed: $e', AgentErrorKinds.device, stack: '$stack');
    }
  }

  String _fail(String message, String kind, {String? stack}) => jsonEncode({
        AgentKeys.ok: false,
        AgentKeys.error: message,
        AgentKeys.errorKind: kind,
        AgentKeys.stack: ?stack,
      });

  Future<Map<String, Object?>> _dispatch(
    String op,
    Map<String, dynamic> request,
  ) async {
    switch (op) {
      case AgentOps.info:
        return _info();
      case AgentOps.dump:
        return _dump();
      case AgentOps.tap:
        return _tap(_point(request));
      case AgentOps.longPress:
        return _longPress(_point(request), _int(request, AgentKeys.ms, 800));
      case AgentOps.swipe:
        return _swipe(
          _point(request),
          _point(request, xKey: AgentKeys.x2, yKey: AgentKeys.y2),
          _int(request, AgentKeys.ms, 300),
        );
      case AgentOps.type:
        return _type(
          _string(request, AgentKeys.text),
          replace: request[AgentKeys.replace] == true,
        );
      case AgentOps.key:
        return _key(_string(request, AgentKeys.name));
      case AgentOps.action:
        return _action(_string(request, AgentKeys.name));
      case AgentOps.screenshot:
        return _screenshot();
      case AgentOps.errors:
        return _errorsOp(clear: request[AgentKeys.clear] == true);
      case AgentOps.settle:
        await _settle(
          max: Duration(milliseconds: _int(request, AgentKeys.ms, 500)),
        );
        return const {};
      case AgentOps.drag:
        return _drag(
          _point(request),
          _point(request, xKey: AgentKeys.x2, yKey: AgentKeys.y2),
          holdMs: _int(request, AgentKeys.holdMs, 600),
          moveMs: _int(request, AgentKeys.ms, 400),
        );
      case AgentOps.perf:
        return _perf(_string(request, AgentKeys.action));
    }
    throw QaAgentException(
      'unknown op "$op"',
      kind: AgentErrorKinds.usage,
    );
  }

  Offset _point(
    Map<String, dynamic> request, {
    String xKey = AgentKeys.x,
    String yKey = AgentKeys.y,
  }) {
    final x = request[xKey];
    final y = request[yKey];
    if (x is! num || y is! num) {
      throw QaAgentException(
        'a point needs numeric $xKey and $yKey',
        kind: AgentErrorKinds.usage,
      );
    }
    final dpr = _flutterView.devicePixelRatio;
    return Offset(x / dpr, y / dpr);
  }

  int _int(Map<String, dynamic> request, String key, int fallback) {
    final value = request[key];
    return value is num ? value.toInt() : fallback;
  }

  String _string(Map<String, dynamic> request, String key) {
    final value = request[key];
    if (value is! String) {
      throw QaAgentException('$key must be a string', kind: AgentErrorKinds.usage);
    }
    return value;
  }

  ui.FlutterView get _flutterView {
    final views = RendererBinding.instance.renderViews;
    if (views.isNotEmpty) return views.first.flutterView;
    final implicit = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (implicit == null) throw QaAgentException('the app has no view yet');
    return implicit;
  }

  RenderView get _renderView {
    final views = RendererBinding.instance.renderViews;
    if (views.isEmpty) throw QaAgentException('the app has no view yet');
    return views.first;
  }

  Future<Map<String, Object?>> _info() async {
    final view = _flutterView;
    final size = view.physicalSize;
    final dpr = view.devicePixelRatio;
    String? documents;
    try {
      documents = (await getApplicationDocumentsDirectory()).path;
    } catch (_) {
      documents = null;
    }
    return {
      AgentKeys.agentVersion: agentProtocolVersion,
      AgentKeys.platform: defaultTargetPlatform.name,
      AgentKeys.dpr: dpr,
      AgentKeys.width: size.width.round(),
      AgentKeys.height: size.height.round(),
      AgentKeys.logicalWidth: size.width / dpr,
      AgentKeys.logicalHeight: size.height / dpr,
      AgentKeys.lifecycle: WidgetsBinding.instance.lifecycleState?.name,
      AgentKeys.semantics: SemanticsBinding.instance.semanticsEnabled,
      AgentKeys.textClient: _textInput.hasAnyClients,
      AgentKeys.documentsPath: documents,
      AgentKeys.qaMode: QaMode.enabled,
      AgentKeys.database: QaMode.databaseName,
      AgentKeys.qaLog: List<String>.of(QaBootstrap.log),
      AgentKeys.qaOutcomes: QaBootstrap.entries.map((e) => e.toJson()).toList(),
      AgentKeys.uptimeMs: DateTime.now().difference(_startedAt).inMilliseconds,
      AgentKeys.rss: ProcessInfo.currentRss,
      AgentKeys.recording: _recordingFrames,
      AgentKeys.firstFrame: WidgetsBinding.instance.firstFrameRasterized,
      AgentKeys.cloud: SyncAvailability.isSupported,
    };
  }

  Future<void> _awaitView() async {
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (RendererBinding.instance.renderViews.isEmpty ||
        !WidgetsBinding.instance.firstFrameRasterized) {
      if (!DateTime.now().isBefore(deadline)) {
        throw QaAgentException(
          'the app has not drawn its first frame yet (still starting?)',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<Map<String, Object?>> _dump() async {
    await _awaitView();
    _semantics ??= SemanticsBinding.instance.ensureSemantics();
    await _pumpOnce();
    final view = _renderView;
    var root = view.owner?.semanticsOwner?.rootSemanticsNode;
    if (root == null) {
      await _settle();
      root = view.owner?.semanticsOwner?.rootSemanticsNode;
    }
    if (root == null) {
      throw QaAgentException(
        'no semantics tree yet (semantics enabled: '
        '${SemanticsBinding.instance.semanticsEnabled})',
      );
    }
    final flutterView = view.flutterView;
    final size = flutterView.physicalSize;
    final screen = Rect.fromLTWH(0, 0, size.width, size.height);
    final nodes = <Map<String, Object?>>[];
    var counter = 0;

    void visit(
      SemanticsNode node,
      Matrix4 parentTransform,
      int parentIndex,
      int depth,
    ) {
      final transform = parentTransform.clone();
      final own = node.transform;
      if (own != null) transform.multiply(own);
      var myIndex = parentIndex;
      var childDepth = depth;
      if (!node.isInvisible) {
        final data = node.getSemanticsData();
        final global = parentIndex == -1
            ? screen
            : MatrixUtils.transformRect(transform, node.rect);
        final clipped = global.intersect(screen);
        final offscreen =
            clipped.isEmpty || clipped.width <= 0 || clipped.height <= 0;
        final shown = offscreen ? global : clipped;
        myIndex = counter++;
        childDepth = depth + 1;
        nodes.add({
          AgentNodeKeys.index: myIndex,
          AgentNodeKeys.parent: parentIndex,
          AgentNodeKeys.depth: depth,
          AgentNodeKeys.label: data.label,
          AgentNodeKeys.value: data.value,
          AgentNodeKeys.hint: data.hint,
          AgentNodeKeys.tooltip: data.tooltip,
          AgentNodeKeys.identifier: data.identifier,
          AgentNodeKeys.rect: [
            shown.left.round(),
            shown.top.round(),
            shown.right.round(),
            shown.bottom.round(),
          ],
          AgentNodeKeys.flags: _flagsOf(data, offscreen: offscreen),
        });
      }
      if (node.mergeAllDescendantsIntoThisNode) return;
      for (final child in node
          .debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)) {
        if (child.isMergedIntoParent) continue;
        visit(child, transform, myIndex, childDepth);
      }
    }

    visit(root, Matrix4.identity(), -1, 0);
    return {
      AgentKeys.dpr: flutterView.devicePixelRatio,
      AgentKeys.width: size.width.round(),
      AgentKeys.height: size.height.round(),
      AgentKeys.nodes: nodes,
    };
  }

  static List<String> _flagsOf(SemanticsData data, {required bool offscreen}) {
    final f = data.flagsCollection;
    final scrolls = f.hasImplicitScrolling ||
        data.hasAction(SemanticsAction.scrollUp) ||
        data.hasAction(SemanticsAction.scrollDown) ||
        data.hasAction(SemanticsAction.scrollLeft) ||
        data.hasAction(SemanticsAction.scrollRight);
    return [
      if (data.hasAction(SemanticsAction.tap)) AgentFlags.click,
      if (data.hasAction(SemanticsAction.longPress)) AgentFlags.long,
      if (scrolls) AgentFlags.scroll,
      if (f.isFocused == ui.Tristate.isTrue) AgentFlags.focused,
      if (f.isEnabled == ui.Tristate.isFalse) AgentFlags.disabled,
      if (f.isChecked != ui.CheckedState.none ||
          f.isToggled != ui.Tristate.none)
        AgentFlags.checkable,
      if (f.isChecked == ui.CheckedState.isTrue ||
          f.isToggled == ui.Tristate.isTrue)
        AgentFlags.checked,
      if (f.isToggled != ui.Tristate.none) AgentFlags.toggle,
      if (f.isSelected == ui.Tristate.isTrue) AgentFlags.selected,
      if (offscreen || f.isHidden) AgentFlags.hidden,
      if (f.isButton) AgentFlags.button,
      if (f.isTextField) AgentFlags.textField,
      if (f.isHeader) AgentFlags.header,
      if (f.isImage) AgentFlags.image,
      if (f.isLink) AgentFlags.link,
      if (f.isSlider) AgentFlags.slider,
      if (f.isReadOnly) AgentFlags.readOnly,
      if (f.isMultiline) AgentFlags.multiline,
      if (f.isObscured) AgentFlags.obscured,
      if (f.scopesRoute) AgentFlags.route,
    ];
  }

  Future<Map<String, Object?>> _tap(Offset at) async {
    await _controller.tapAt(at);
    await _settle();
    return const {};
  }

  Future<Map<String, Object?>> _longPress(Offset at, int ms) async {
    final gesture = await _controller.startGesture(at);
    await Future<void>.delayed(Duration(milliseconds: ms.clamp(100, 10000)));
    await gesture.up();
    await _settle();
    return const {};
  }

  Future<Map<String, Object?>> _drag(
    Offset from,
    Offset to, {
    required int holdMs,
    required int moveMs,
  }) async {
    final gesture = await _controller.startGesture(from);
    final hold = Duration(milliseconds: holdMs.clamp(0, 10000));
    await Future<void>.delayed(hold);
    final travel = Duration(milliseconds: moveMs.clamp(50, 10000));
    final steps = (travel.inMilliseconds / 16).ceil().clamp(2, 600);
    for (var i = 1; i <= steps; i++) {
      final at = Offset.lerp(from, to, i / steps)!;
      await gesture.moveTo(at, timeStamp: hold + travel * i ~/ steps);
      await Future<void>.delayed(travel ~/ steps);
    }
    await gesture.up(timeStamp: hold + travel);
    await _settle();
    return const {};
  }

  Map<String, Object?> _perf(String action) {
    switch (action) {
      case AgentPerfActions.start:
        _semantics?.dispose();
        _semantics = null;
        _timings.clear();
        _recordingFrames = true;
        _recordingSince = DateTime.now();
        return {AgentKeys.recording: true};
      case AgentPerfActions.stop:
        _recordingFrames = false;
        return _perfReport();
      case AgentPerfActions.read:
        return _perfReport();
    }
    throw QaAgentException(
      'perf action must be start, stop or read',
      kind: AgentErrorKinds.usage,
    );
  }

  Map<String, Object?> _perfReport() {
    final since = _recordingSince;
    Map<String, Object?> stats(Iterable<Duration> values) {
      final sorted = values.map((d) => d.inMicroseconds / 1000).toList()..sort();
      if (sorted.isEmpty) return const {'p50': 0, 'p90': 0, 'max': 0};
      double at(double q) => sorted[((sorted.length - 1) * q).round()];
      return {
        'p50': double.parse(at(0.5).toStringAsFixed(2)),
        'p90': double.parse(at(0.9).toStringAsFixed(2)),
        'max': double.parse(sorted.last.toStringAsFixed(2)),
      };
    }

    const budget = Duration(microseconds: 16667);
    return {
      AgentKeys.recording: _recordingFrames,
      AgentKeys.frames: _timings.length,
      AgentKeys.elapsedMs: since == null
          ? 0
          : DateTime.now().difference(since).inMilliseconds,
      AgentKeys.build: stats(_timings.map((t) => t.buildDuration)),
      AgentKeys.raster: stats(_timings.map((t) => t.rasterDuration)),
      AgentKeys.total: stats(_timings.map((t) => t.totalSpan)),
      AgentKeys.jank: _timings
          .where((t) => t.buildDuration > budget || t.rasterDuration > budget)
          .length,
    };
  }

  Future<Map<String, Object?>> _swipe(Offset from, Offset to, int ms) async {
    final duration = Duration(milliseconds: ms.clamp(50, 10000));
    await _controller.timedDragFrom(from, to - from, duration);
    await _settle();
    return const {};
  }

  Future<Map<String, Object?>> _type(String text, {required bool replace}) async {
    _requireTextClient();
    if (text.isEmpty && !replace) {
      throw QaAgentException('nothing to type', kind: AgentErrorKinds.usage);
    }
    final current = _currentValue();
    final TextEditingValue next;
    if (replace) {
      next = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    } else {
      final selection = _selectionOf(current);
      next = current.replaced(selection, text).copyWith(
            selection:
                TextSelection.collapsed(offset: selection.start + text.length),
            composing: TextRange.empty,
          );
    }
    _commit(next);
    await _settle();
    return {
      AgentKeys.text: next.text,
      AgentKeys.selection: next.selection.extentOffset,
    };
  }

  Future<Map<String, Object?>> _backspace() async {
    final current = _currentValue();
    final selection = _selectionOf(current);
    if (!selection.isCollapsed) {
      final next = current.replaced(selection, '').copyWith(
            selection: TextSelection.collapsed(offset: selection.start),
            composing: TextRange.empty,
          );
      _commit(next);
      await _settle();
      return {AgentKeys.text: next.text, AgentKeys.selection: selection.start};
    }
    if (selection.start <= 0) {
      return {AgentKeys.text: current.text, AgentKeys.selection: 0};
    }
    var start = selection.start - 1;
    final text = current.text;
    if (start > 0 &&
        _isLowSurrogate(text.codeUnitAt(start)) &&
        _isHighSurrogate(text.codeUnitAt(start - 1))) {
      start--;
    }
    final next = current
        .replaced(TextRange(start: start, end: selection.start), '')
        .copyWith(
          selection: TextSelection.collapsed(offset: start),
          composing: TextRange.empty,
        );
    _commit(next);
    await _settle();
    return {AgentKeys.text: next.text, AgentKeys.selection: start};
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  static bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

  void _requireTextClient() {
    if (!_textInput.hasAnyClients) {
      throw QaAgentException(
        'no text field is focused — tap a field first',
        kind: AgentErrorKinds.target,
      );
    }
  }

  TextEditingValue _currentValue() {
    final state = _textInput.editingState;
    if (state == null) return TextEditingValue.empty;
    return TextEditingValue.fromJSON(state);
  }

  static TextSelection _selectionOf(TextEditingValue value) {
    final selection = value.selection;
    if (selection.isValid &&
        selection.start <= value.text.length &&
        selection.end <= value.text.length) {
      return selection;
    }
    return TextSelection.collapsed(offset: value.text.length);
  }

  void _commit(TextEditingValue next) {
    _textInput.updateEditingValue(next);
    _textInput.editingState = next.toJSON();
  }

  Future<Map<String, Object?>> _action(String rawName) async {
    _requireTextClient();
    final name = rawName.trim();
    final action = TextInputAction.values
        .where((a) => a.name.toLowerCase() == name.toLowerCase())
        .toList();
    if (action.isEmpty) {
      throw QaAgentException(
        'unknown text input action "$rawName"; one of '
        '${agentTextActions.join(', ')}',
        kind: AgentErrorKinds.usage,
      );
    }
    await _textInput.receiveAction(action.single);
    await _settle();
    return {AgentKeys.name: action.single.name};
  }

  TextInputAction _configuredAction() {
    final args = _textInput.setClientArgs;
    final configured = args?['inputAction'] as String?;
    if (configured != null) {
      for (final action in TextInputAction.values) {
        if (action.toString() == configured) return action;
      }
    }
    final type = args?['inputType'];
    if (type is Map && type['name'] == 'TextInputType.multiline') {
      return TextInputAction.newline;
    }
    return TextInputAction.done;
  }

  Future<Map<String, Object?>> _key(String rawName) async {
    final name = rawName.trim().toLowerCase();
    if (name == 'back') {
      final popped = await _back();
      return {AgentKeys.name: 'back', AgentKeys.popped: popped};
    }
    if (agentTextActions.contains(name)) return _action(name);
    if (androidOnlyKeys.contains(name)) {
      throw QaAgentException(
        '"$rawName" is an Android system key; the agent has no equivalent on '
        '${defaultTargetPlatform.name}',
        kind: AgentErrorKinds.usage,
      );
    }
    if (name.contains('+')) return _chord(name);
    final logical = agentKeyAliases[name];
    if (logical == null) {
      throw QaAgentException(
        'unknown key "$rawName"; one of back, '
        '${agentKeyAliases.keys.join(', ')}, ${agentTextActions.join(', ')}, '
        'or a chord such as meta+z, ctrl+shift+z, shift+tab',
        kind: AgentErrorKinds.usage,
      );
    }
    if (_textInput.hasAnyClients) {
      if (logical == 'enter') {
        final action = _configuredAction();
        await _textInput.receiveAction(action);
        await _settle();
        return {AgentKeys.name: 'enter', 'action': action.name};
      }
      if (logical == 'backspace') return _backspace();
      if (logical == 'space') return _type(' ', replace: false);
    }
    final key = _logicalKeys[logical]!;
    final handled = await simulateKeyDownEvent(key);
    await simulateKeyUpEvent(key);
    await _settle();
    return {AgentKeys.name: logical, 'handled': handled};
  }

  Future<bool> _back() async {
    final navigators = find.byType(Navigator);
    if (navigators.evaluate().isEmpty) return false;
    final root = _controller.state<NavigatorState>(navigators.first);
    final handled = await root.maybePop();
    await _settle();
    return handled;
  }

  Future<Map<String, Object?>> _chord(String spec) async {
    final parts = spec.split('+').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) {
      throw QaAgentException('a chord needs modifier+key, got "$spec"', kind: AgentErrorKinds.usage);
    }
    final modifiers = <LogicalKeyboardKey>[];
    for (final part in parts.sublist(0, parts.length - 1)) {
      final modifier = agentModifierKeys[part];
      if (modifier == null) {
        throw QaAgentException(
          '"$part" is not a modifier; use ${agentModifierKeys.keys.join(', ')}',
          kind: AgentErrorKinds.usage,
        );
      }
      modifiers.add(_modifierKeys[modifier]!);
    }
    final key = _lookupKey(parts.last);
    for (final modifier in modifiers) {
      await simulateKeyDownEvent(modifier);
    }
    final handled = await simulateKeyDownEvent(key);
    await simulateKeyUpEvent(key);
    for (final modifier in modifiers.reversed) {
      await simulateKeyUpEvent(modifier);
    }
    await _settle();
    return {AgentKeys.name: spec, 'handled': handled};
  }

  static const Map<String, LogicalKeyboardKey> _modifierKeys = {
    'controlLeft': LogicalKeyboardKey.controlLeft,
    'shiftLeft': LogicalKeyboardKey.shiftLeft,
    'altLeft': LogicalKeyboardKey.altLeft,
    'metaLeft': LogicalKeyboardKey.metaLeft,
  };

  LogicalKeyboardKey _lookupKey(String name) {
    final alias = agentKeyAliases[name.toLowerCase()];
    if (alias != null && _logicalKeys.containsKey(alias)) return _logicalKeys[alias]!;
    for (final key in LogicalKeyboardKey.knownLogicalKeys) {
      if (key.keyLabel.toLowerCase() == name.toLowerCase() && key.keyLabel.isNotEmpty) {
        return key;
      }
    }
    throw QaAgentException(
      'unknown key "$name" in chord',
      kind: AgentErrorKinds.usage,
    );
  }

  Future<Map<String, Object?>> _screenshot() async {
    await _awaitView();
    await _pumpOnce();
    final view = _renderView;
    final flutterView = view.flutterView;
    final size = flutterView.physicalSize;
    final image = await _InspectorShots().capture(
      view,
      width: size.width,
      height: size.height,
      pixelRatio: flutterView.devicePixelRatio,
    );
    if (image == null) {
      throw QaAgentException('the inspector produced no image');
    }
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw QaAgentException('PNG encoding failed');
      return {
        AgentKeys.png: base64Encode(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        ),
        AgentKeys.width: image.width,
        AgentKeys.height: image.height,
      };
    } finally {
      image.dispose();
    }
  }

  Map<String, Object?> _errorsOp({required bool clear}) {
    final snapshot = List<String>.of(_errors);
    if (clear) _errors.clear();
    return {AgentKeys.list: snapshot};
  }

  void _installErrorHooks() {
    if (_hooksInstalled) return;
    _hooksInstalled = true;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final context = details.context;
      _record(
        '${details.exceptionAsString()}'
        '${context == null ? '' : ' (${context.toDescription()})'}',
      );
      previous?.call(details);
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _record('$error');
      return previousPlatform?.call(error, stack) ?? false;
    };
  }

  void _record(String message) {
    _errors.add(
      '${DateTime.now().toIso8601String().substring(11, 23)} $message',
    );
    if (_errors.length > _errorLimit) _errors.removeAt(0);
  }

  Future<void> _pumpOnce() async {
    final binding = WidgetsBinding.instance;
    if (!binding.hasScheduledFrame) return;
    try {
      await binding.endOfFrame.timeout(_frameCap);
    } on TimeoutException {
      return;
    }
  }

  Future<void> _settle({Duration max = _settleCap}) async {
    final binding = WidgetsBinding.instance;
    final deadline = DateTime.now().add(max);
    do {
      try {
        await binding.endOfFrame.timeout(_frameCap);
      } on TimeoutException {
        return;
      }
    } while (binding.hasScheduledFrame && DateTime.now().isBefore(deadline));
  }
}

class _InspectorShots with WidgetInspectorService {
  Future<ui.Image?> capture(
    RenderObject target, {
    required double width,
    required double height,
    required double pixelRatio,
  }) =>
      screenshot(target, width: width, height: height, maxPixelRatio: pixelRatio);
}
