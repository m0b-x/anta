abstract final class AgentOps {
  static const String info = 'info';
  static const String dump = 'dump';
  static const String tap = 'tap';
  static const String longPress = 'longpress';
  static const String swipe = 'swipe';
  static const String type = 'type';
  static const String key = 'key';
  static const String action = 'action';
  static const String screenshot = 'screenshot';
  static const String errors = 'errors';
  static const String settle = 'settle';
  static const String drag = 'drag';
  static const String perf = 'perf';

  /// Run-time overrides on a driver build: text scale, locale, theme.
  static const String set = 'set';

  /// Scrolls the semantics node [AgentNodeKeys.semanticsId] names into view
  /// with `SemanticsAction.showOnScreen`, the action TalkBack uses, so a row
  /// a sheet has scrolled past is reached without a flow-authored swipe.
  static const String reveal = 'reveal';
}

abstract final class AgentKeys {
  static const String op = 'op';
  static const String ok = 'ok';
  static const String error = 'error';
  static const String errorKind = 'kind';
  static const String stack = 'stack';

  static const String x = 'x';
  static const String y = 'y';

  static const String textScale = 'textScale';
  static const String locale = 'locale';
  static const String themeMode = 'themeMode';
  static const String x2 = 'x2';
  static const String y2 = 'y2';
  static const String ms = 'ms';
  static const String text = 'text';
  static const String replace = 'replace';
  static const String name = 'name';
  static const String clear = 'clear';
  static const String holdMs = 'holdMs';
  static const String action = 'action';
  static const String rss = 'rssBytes';
  static const String firstFrame = 'firstFrame';
  static const String cloud = 'cloud';

  static const String platform = 'platform';
  static const String dpr = 'dpr';
  static const String width = 'width';
  static const String height = 'height';
  static const String logicalWidth = 'logicalWidth';
  static const String logicalHeight = 'logicalHeight';
  static const String lifecycle = 'lifecycle';
  static const String semantics = 'semantics';
  static const String textClient = 'textClient';
  static const String documentsPath = 'documentsPath';
  static const String qaLog = 'qaLog';
  static const String qaOutcomes = 'qaOutcomes';
  static const String qaMode = 'qaMode';
  static const String database = 'database';
  static const String agentVersion = 'agentVersion';
  static const String uptimeMs = 'uptimeMs';

  static const String nodes = 'nodes';
  static const String png = 'png';
  static const String list = 'errors';
  static const String selection = 'selection';
  static const String popped = 'popped';
  static const String frames = 'frames';
  static const String build = 'build';
  static const String raster = 'raster';
  static const String total = 'total';
  static const String jank = 'jank';
  static const String recording = 'recording';
  static const String elapsedMs = 'elapsedMs';
}

abstract final class AgentPerfActions {
  static const String start = 'start';
  static const String stop = 'stop';
  static const String read = 'read';
}

const Map<String, String> agentModifierKeys = {
  'ctrl': 'controlLeft',
  'control': 'controlLeft',
  'shift': 'shiftLeft',
  'alt': 'altLeft',
  'option': 'altLeft',
  'meta': 'metaLeft',
  'cmd': 'metaLeft',
  'command': 'metaLeft',
  'win': 'metaLeft',
};

abstract final class AgentNodeKeys {
  static const String index = 'i';
  static const String parent = 'p';
  static const String depth = 'd';
  static const String label = 'l';
  static const String value = 'v';
  static const String hint = 'h';
  static const String tooltip = 't';
  static const String identifier = 'id';
  static const String rect = 'r';
  static const String flags = 'f';

  /// `SemanticsNode.id`: what `reveal` names a node by, since the flat
  /// index `i` is only an order within one dump.
  static const String semanticsId = 'n';
}

abstract final class AgentFlags {
  static const String click = 'click';
  static const String long = 'long';
  static const String scroll = 'scroll';
  static const String focused = 'focused';
  static const String disabled = 'disabled';
  static const String checkable = 'checkable';
  static const String checked = 'checked';
  static const String toggle = 'toggle';
  static const String selected = 'selected';
  /// The framework's `isHidden`: kept in the tree while scrolled out.
  static const String hidden = 'hidden';

  /// The rect lies outside the screen without the framework hiding it (a
  /// route sliding in). Additive within protocol 2: a dump without it reads
  /// as before, with `hidden` covering both kinds.
  static const String offscreen = 'offscreen';
  static const String button = 'button';
  static const String textField = 'textfield';
  static const String header = 'header';
  static const String image = 'image';
  static const String link = 'link';
  static const String slider = 'slider';
  static const String readOnly = 'readonly';
  static const String multiline = 'multiline';
  static const String obscured = 'obscured';
  static const String route = 'route';
}

abstract final class AgentErrorKinds {
  static const String target = 'target';
  static const String usage = 'usage';
  static const String device = 'device';
}

/// The agent's protocol, compiled into the APK: v2 added node ids to the
/// dump and the `reveal` op.
const int agentProtocolVersion = 2;

/// What to say when the installed agent is older than this tool, or null
/// when it is current. The agent ships inside the driver build, so a tool
/// change alone never updates it.
String? agentVersionMismatch(int installed) => installed >= agentProtocolVersion
    ? null
    : 'installed agent is v$installed, this tool needs v$agentProtocolVersion '
        '— `qa build` then `qa install`';

/// How long the agent waits after an action for the app to stop scheduling
/// frames. A ripple keeps frames coming, so most taps pay the whole cap,
/// while every flow then waits for what it needs explicitly: in a sharded
/// calendar pass a tap measured p50 520 ms at a 500 ms cap and 245 ms at
/// this one (2026-10-23). A route still closing or a scroll still animating
/// is waited out past the cap (the agent's `screenMoving`): without that a
/// short cap left a flow's next target unbuilt.
const int agentSettleCapMs = 150;

const String driverExtensionMethod = 'ext.flutter.driver';

const List<String> agentTextActions = [
  'done',
  'go',
  'search',
  'send',
  'next',
  'previous',
  'newline',
  'unspecified',
  'none',
];

const Map<String, String> agentKeyAliases = {
  'back': 'back',
  'enter': 'enter',
  'return': 'enter',
  'tab': 'tab',
  'esc': 'escape',
  'escape': 'escape',
  'del': 'backspace',
  'delete': 'backspace',
  'backspace': 'backspace',
  'up': 'arrowUp',
  'down': 'arrowDown',
  'left': 'arrowLeft',
  'right': 'arrowRight',
  'pageup': 'pageUp',
  'pagedown': 'pageDown',
  'space': 'space',
};

const Set<String> androidOnlyKeys = {
  'home',
  'menu',
  'power',
  'app_switch',
  'recents',
};
