import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/lock_screen_state.dart';

/// The rule that decides whether the app may be seen on a locked phone.
///
/// A ringing alarm lifts the whole activity above the keyguard; the alarm page
/// is the only thing meant to be there. Everything else is covered while
/// [LockScreenState.mustCover] holds, so each case below is a moment a note or
/// the ledger would otherwise be readable without a PIN.
void main() {
  late LockScreenState state;

  setUp(() => state = LockScreenState());

  test('nothing is covered on an unlocked phone', () {
    expect(state.locked, isFalse);
    expect(state.mustCover, isFalse);

    // Not even with an alarm page nowhere in sight.
    state.alarmSurfaceHidden(Object());
    expect(state.mustCover, isFalse);
  });

  test('a locked phone is covered until an alarm page is on top', () {
    state.setLocked(true);
    expect(state.mustCover, isTrue);

    final page = Object();
    state.alarmSurfaceShown(page);
    expect(state.mustCover, isFalse);

    state.alarmSurfaceHidden(page);
    expect(state.mustCover, isTrue);
  });

  test('unlocking lifts the cover with no alarm page at all', () {
    state.setLocked(true);
    state.setLocked(false);
    expect(state.mustCover, isFalse);
  });

  test('two alarm pages: the cover stays off until both are gone', () {
    // A second alarm ringing over the first pushes a second page; the first
    // reports itself covered, the second on top.
    state.setLocked(true);
    final first = Object();
    final second = Object();
    state.alarmSurfaceShown(first);
    state.alarmSurfaceHidden(first);
    state.alarmSurfaceShown(second);
    expect(state.mustCover, isFalse);

    state.alarmSurfaceHidden(second);
    expect(state.mustCover, isTrue);
  });

  test('a page reporting twice cannot leave the cover open behind it', () {
    state.setLocked(true);
    final page = Object();
    state.alarmSurfaceShown(page);
    state.alarmSurfaceShown(page);
    state.alarmSurfaceHidden(page);
    expect(state.mustCover, isTrue);
  });

  test('changes notifies when either input moves', () {
    var notifications = 0;
    state.changes.addListener(() => notifications++);

    state.setLocked(true);
    state.alarmSurfaceShown(Object());
    expect(notifications, 2);

    // The same answer again is not a change.
    state.setLocked(true);
    expect(notifications, 2);
  });

  group('refresh', () {
    test('takes the platform answer', () async {
      state.query = () async => true;
      await state.refresh();
      expect(state.locked, isTrue);

      state.query = () async => false;
      await state.refresh();
      expect(state.locked, isFalse);
    });

    test('a failed read keeps the last answer', () async {
      // A cover that stays is a nuisance; one that lifts on an error shows
      // the app to whoever is holding the locked phone.
      state.setLocked(true);
      state.query = () async => throw StateError('channel gone');
      await state.refresh();
      expect(state.locked, isTrue);
    });

    test('does nothing where nobody can answer', () async {
      state.setLocked(true);
      await state.refresh();
      expect(state.locked, isTrue);
    });
  });
}
