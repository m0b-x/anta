import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/nav_destination.dart';
import 'package:anta/models/restore_location_mode.dart';

/// The remembered stack is replayed on cold launch, which is the one moment
/// nothing can be re-asked of the user. So what matters here is that decoding
/// is *total*: every malformed, truncated or newer-than-this-build value has a
/// defined, non-throwing answer, and the answer is always a coherent chain —
/// a prefix in which every entry's parent precedes it.
void main() {
  group('round trip', () {
    test('a full chain survives encode/decode', () {
      final stack = [
        NavDestination.folder(folderId: 'f1', title: 'Training'),
        NavDestination.note(noteId: 'n1', folderId: 'f1'),
        const NavDestination(NavDestinationKind.syncSettings),
      ];

      expect(NavDestination.decodeStack(NavDestination.encodeStack(stack)),
          stack);
    });

    test('an empty stack round-trips as empty, not as absent', () {
      final encoded = NavDestination.encodeStack(const []);

      expect(encoded, isNot(isEmpty));
      expect(NavDestination.decodeStack(encoded), isEmpty);
    });

    test('counter management keeps an optional note id, and omits an empty one',
        () {
      expect(NavDestination.counterManagement(noteId: 'n1').noteId, 'n1');
      expect(NavDestination.counterManagement().noteId, isNull);
      expect(NavDestination.counterManagement(noteId: '').params, isEmpty);
    });
  });

  group('degradation', () {
    test('a kind written by a newer build truncates the stack there', () {
      final raw = jsonEncode({
        'v': NavDestination.stackVersion,
        'stack': [
          {'k': 'folder', 'p': {'folderId': 'f1', 'title': 'Training'}},
          {'k': 'timeMachine'},
          {'k': 'calendar'},
        ],
      });

      expect(NavDestination.decodeStack(raw), [
        NavDestination.folder(folderId: 'f1', title: 'Training'),
      ]);
    });

    test('an unrecognised envelope version restores nothing', () {
      final raw = jsonEncode({
        'v': NavDestination.stackVersion + 1,
        'stack': [
          {'k': 'calendar'},
        ],
      });

      expect(NavDestination.decodeStack(raw), isEmpty);
    });

    test('an entry missing its required params truncates rather than throws',
        () {
      final raw = jsonEncode({
        'v': NavDestination.stackVersion,
        'stack': [
          {'k': 'calendar'},
          {'k': 'note', 'p': {'noteId': 'n1'}},
        ],
      });

      expect(NavDestination.decodeStack(raw), [
        const NavDestination(NavDestinationKind.calendar),
      ]);
    });

    test('garbage never throws', () {
      expect(NavDestination.decodeStack(null), isEmpty);
      expect(NavDestination.decodeStack(''), isEmpty);
      expect(NavDestination.decodeStack('not json'), isEmpty);
      expect(NavDestination.decodeStack('{'), isEmpty);
      expect(NavDestination.decodeStack('[]'), isEmpty);
    });
  });

  group('kind properties', () {
    test('only the drawer-owned settings pages reopen the drawer', () {
      final reopening = NavDestinationKind.values
          .where((kind) => kind.reopensDrawerOnPop)
          .toSet();

      expect(reopening, {
        NavDestinationKind.databaseSettings,
        NavDestinationKind.settings,
        NavDestinationKind.syncSettings,
        NavDestinationKind.counterManagement,
      });
    });

    test('the calendar is a feature, not a setting, so it raises no drawer',
        () {
      expect(NavDestinationKind.calendar.reopensDrawerOnPop, isFalse);
    });
  });

  group('restore modes', () {
    final stack = [
      NavDestination.folder(folderId: 'f1', title: 'Training'),
      NavDestination.note(noteId: 'n1', folderId: 'f1'),
      const NavDestination(NavDestinationKind.calendar),
      const NavDestination(NavDestinationKind.calendarSettings),
    ];

    test('everything replays the whole chain', () {
      expect(RestoreLocationMode.everything.apply(stack), stack);
    });

    test('off replays nothing', () {
      expect(RestoreLocationMode.off.apply(stack), isEmpty);
    });

    test('notes takes a prefix, so the Back path it leaves is one that existed',
        () {
      expect(RestoreLocationMode.notes.apply(stack), stack.take(2));
    });

    test('notes drops a chain that starts above the substrate', () {
      expect(
        RestoreLocationMode.notes.apply([
          const NavDestination(NavDestinationKind.calendar),
          NavDestination.folder(folderId: 'f1', title: 'Training'),
        ]),
        isEmpty,
      );
    });

    test('an unknown stored mode reads as everything', () {
      expect(RestoreLocationMode.fromName('turbo'),
          RestoreLocationMode.everything);
      expect(RestoreLocationMode.fromName(null),
          RestoreLocationMode.everything);
    });
  });
}
