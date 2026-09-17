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
}

abstract final class AgentKeys {
  static const String op = 'op';
  static const String ok = 'ok';
  static const String error = 'error';
  static const String errorKind = 'kind';
  static const String stack = 'stack';

  static const String x = 'x';
  static const String y = 'y';
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
  static const String hidden = 'hidden';
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

const int agentProtocolVersion = 1;

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
