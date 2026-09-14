import 'errors.dart';

/// Quotes [value] for the device shell that `adb shell` hands the command to.
///
/// Single quotes stop `sh` from expanding `$`, backticks, `*`, `~`, `#` and
/// friends; an embedded quote is closed, escaped and reopened.
String shellSingleQuote(String value) {
  final escaped = value.replaceAll("'", r"'\''");
  return "'$escaped'";
}

/// Escapes [text] for `adb shell input text`.
///
/// `input text` reads `%s` as a space, so spaces are substituted first and the
/// whole argument is then single-quoted for the remote shell. Non-ASCII is
/// rejected: the Android input command cannot type it.
String escapeForInputText(String text) {
  if (text.isEmpty) {
    throw UsageFailure('nothing to type: the text is empty');
  }
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit == 0x0a || unit == 0x0d) {
      throw UsageFailure(
        'cannot type a line break with `input text`; use `key enter` instead.',
      );
    }
    if (unit == 0x09) {
      throw UsageFailure(
        'cannot type a tab with `input text`; use `key tab` instead.',
      );
    }
    if (unit < 0x20 || unit > 0x7e) {
      throw UsageFailure(
        'cannot type "${text[i]}" (U+${unit.toRadixString(16).padLeft(4, '0').toUpperCase()}): '
        '`adb shell input text` is ASCII only. Use the Flutter Driver path '
        'instead (Dart MCP `flutter_driver_command` with command "enter_text"), '
        'which types any Unicode.',
      );
    }
  }
  return shellSingleQuote(text.replaceAll(' ', '%s'));
}

const Map<String, String> _keyAliases = {
  'back': 'KEYCODE_BACK',
  'home': 'KEYCODE_HOME',
  'enter': 'KEYCODE_ENTER',
  'del': 'KEYCODE_DEL',
  'delete': 'KEYCODE_DEL',
  'backspace': 'KEYCODE_DEL',
  'tab': 'KEYCODE_TAB',
  'esc': 'KEYCODE_ESCAPE',
  'escape': 'KEYCODE_ESCAPE',
  'menu': 'KEYCODE_MENU',
  'search': 'KEYCODE_SEARCH',
  'up': 'KEYCODE_DPAD_UP',
  'down': 'KEYCODE_DPAD_DOWN',
  'left': 'KEYCODE_DPAD_LEFT',
  'right': 'KEYCODE_DPAD_RIGHT',
  'power': 'KEYCODE_POWER',
  'app_switch': 'KEYCODE_APP_SWITCH',
  'recents': 'KEYCODE_APP_SWITCH',
};

/// Resolves a friendly key name or a raw `KEYCODE_*` / numeric keycode.
String resolveKeycode(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) throw UsageFailure('no key given');
  final alias = _keyAliases[trimmed.toLowerCase()];
  if (alias != null) return alias;
  if (RegExp(r'^KEYCODE_[A-Z0-9_]+$').hasMatch(trimmed)) return trimmed;
  if (RegExp(r'^\d+$').hasMatch(trimmed)) return trimmed;
  throw UsageFailure(
    'unknown key "$name". Use one of ${_keyAliases.keys.join(', ')} '
    'or a raw KEYCODE_* name.',
  );
}
