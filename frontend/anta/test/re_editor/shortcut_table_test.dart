import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// The Windows and Linux shortcut table (the one every non-macOS desktop
/// build reads; widget tests are not macOS, so the default builder hands
/// it back). It follows the platform convention: Ctrl+←/→ move by word and
/// Shift extends, Home/End reach the line edges, Ctrl+Backspace and
/// Ctrl+Delete delete a word, and the whole-line deletes add Shift.
void main() {
  const builder = DefaultCodeShortcutsActivatorsBuilder();

  String describe(ShortcutActivator activator) {
    final single = activator as SingleActivator;
    return [
      if (single.control) 'Ctrl',
      if (single.shift) 'Shift',
      if (single.alt) 'Alt',
      if (single.meta) 'Meta',
      single.trigger.keyLabel,
    ].join('+');
  }

  List<String> keysOf(CodeShortcutType type) =>
      (builder.build(type) ?? const <ShortcutActivator>[])
          .map(describe)
          .toList();

  final ctrlLeft = describe(
    const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true),
  );
  final ctrlRight = describe(
    const SingleActivator(LogicalKeyboardKey.arrowRight, control: true),
  );

  test('Ctrl+arrows move by word, Shift extends by word', () {
    expect(keysOf(CodeShortcutType.cursorMoveWordBoundaryBackward), [
      ctrlLeft,
      'Alt+${LogicalKeyboardKey.arrowLeft.keyLabel}',
    ]);
    expect(keysOf(CodeShortcutType.cursorMoveWordBoundaryForward), [
      ctrlRight,
      'Alt+${LogicalKeyboardKey.arrowRight.keyLabel}',
    ]);
    // The controller's extend-by-word names are reversed (…Forward moves
    // the extent left), so the physical ← binds Forward, as on macOS;
    // `word_selection_desktop_test.dart` presses the keys.
    expect(keysOf(CodeShortcutType.selectionExtendWordBoundaryForward), [
      'Ctrl+Shift+${LogicalKeyboardKey.arrowLeft.keyLabel}',
      'Shift+Alt+${LogicalKeyboardKey.arrowLeft.keyLabel}',
    ]);
    expect(keysOf(CodeShortcutType.selectionExtendWordBoundaryBackward), [
      'Ctrl+Shift+${LogicalKeyboardKey.arrowRight.keyLabel}',
      'Shift+Alt+${LogicalKeyboardKey.arrowRight.keyLabel}',
    ]);
  });

  test('Ctrl+Y redoes beside Ctrl+Shift+Z', () {
    expect(keysOf(CodeShortcutType.redo), [
      'Ctrl+Shift+${LogicalKeyboardKey.keyZ.keyLabel}',
      'Ctrl+${LogicalKeyboardKey.keyY.keyLabel}',
    ]);
  });

  test('Home and End alone reach the line edges', () {
    expect(keysOf(CodeShortcutType.cursorMoveLineStart), [
      LogicalKeyboardKey.home.keyLabel,
    ]);
    expect(keysOf(CodeShortcutType.cursorMoveLineEnd), [
      LogicalKeyboardKey.end.keyLabel,
    ]);
  });

  test('Ctrl+Backspace and Ctrl+Delete delete a word; the line deletes '
      'take Shift too', () {
    final backspace = LogicalKeyboardKey.backspace.keyLabel;
    final delete = LogicalKeyboardKey.delete.keyLabel;
    expect(
      keysOf(CodeShortcutType.wordDeleteBackward),
      contains('Ctrl+$backspace'),
    );
    expect(
      keysOf(CodeShortcutType.wordDeleteForward),
      contains('Ctrl+$delete'),
    );
    expect(keysOf(CodeShortcutType.lineDeleteBackward), [
      'Ctrl+Shift+$backspace',
    ]);
    expect(keysOf(CodeShortcutType.lineDeleteForward), ['Ctrl+Shift+$delete']);
  });

  test('no chord is bound to two shortcuts', () {
    final owners = <String, CodeShortcutType>{};
    for (final type in CodeShortcutType.values) {
      for (final key in keysOf(type)) {
        expect(
          owners.containsKey(key),
          isFalse,
          reason: '$key is bound to both ${owners[key]} and $type',
        );
        owners[key] = type;
      }
    }
  });
}
