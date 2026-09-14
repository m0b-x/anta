import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/ui_tree.dart';

String _fixture(String name) =>
    File('test/qa/fixtures/$name').readAsStringSync();

void main() {
  group('UiRect', () {
    test('parses uiautomator bounds', () {
      final rect = UiRect.tryParse('[48,462][1232,606]')!;
      expect(rect.left, 48);
      expect(rect.top, 462);
      expect(rect.right, 1232);
      expect(rect.bottom, 606);
      expect(rect.width, 1184);
      expect(rect.height, 144);
      expect(rect.centreX, 640);
      expect(rect.centreY, 534);
    });

    test('rejects anything else', () {
      expect(UiRect.tryParse(''), isNull);
      expect(UiRect.tryParse('48,462'), isNull);
    });

    test('treats a collapsed rectangle as empty', () {
      expect(const UiRect(10, 10, 10, 40).isEmpty, isTrue);
      expect(const UiRect(10, 10, 40, 10).isEmpty, isTrue);
      expect(const UiRect(10, 10, 40, 40).isEmpty, isFalse);
    });
  });

  group('UiTree.parse on a real ANTA dump', () {
    late UiTree tree;

    setUp(() => tree = UiTree.parse(_fixture('folder_root_dump.xml')));

    test('flattens every sized node with a stable index', () {
      expect(tree.nodes, isNotEmpty);
      for (var i = 0; i < tree.nodes.length; i++) {
        expect(tree.nodes[i].index, i);
      }
    });

    test('drops zero-size nodes', () {
      expect(tree.nodes.every((n) => !n.bounds.isEmpty), isTrue);
    });

    test('reads the app bar buttons with their content descriptions', () {
      final labels = tree.nodes.map((n) => n.contentDesc).toList();
      expect(labels, contains('Open navigation menu'));
      expect(labels, contains('Search all notes'));
      expect(labels, contains('Show menu'));
      expect(labels, contains('New folder'));
    });

    test('keeps the clickable and long-clickable flags', () {
      final training =
          tree.nodes.firstWhere((n) => n.contentDesc.startsWith('Training'));
      expect(training.clickable, isTrue);
      expect(training.longClickable, isTrue);
      expect(training.enabled, isTrue);
    });

    test('records parent links so an ancestor can be walked to', () {
      final menu =
          tree.nodes.firstWhere((n) => n.contentDesc == 'Open navigation menu');
      expect(menu.parentIndex, greaterThanOrEqualTo(0));
      expect(tree.parentOf(menu), isNotNull);
      expect(tree.clickableSelfOrAncestor(menu), same(menu));
    });

    test('describe() is one compact line', () {
      final search =
          tree.nodes.firstWhere((n) => n.contentDesc == 'Search all notes');
      expect(search.describe(),
          '#${search.index}  Button  "Search all notes"  [992,156][1136,300]  click');
    });

    test('shortClass and shortId strip their prefixes', () {
      final content =
          tree.nodes.firstWhere((n) => n.resourceId == 'android:id/content');
      expect(content.shortId, 'content');
      expect(content.shortClass, 'FrameLayout');
    });
  });

  group('UiTree.parse on the search screen', () {
    late UiTree tree;

    setUp(() => tree = UiTree.parse(_fixture('search_results_dump.xml')));

    test('reads the text attribute of the focused field', () {
      final field = tree.nodes.firstWhere((n) => n.className.endsWith('EditText'));
      expect(field.text, 'squat');
      expect(field.focused, isTrue);
    });

    test('interesting keeps labelled, clickable and scrollable nodes only', () {
      final interesting = tree.nodes.where((n) => n.interesting).toList();
      expect(interesting.length, lessThan(tree.nodes.length));
      expect(
        interesting.every((n) => n.hasLabel || n.clickable || n.scrollable),
        isTrue,
      );
    });
  });

  group('UiTree.parse on a scrollable folder listing', () {
    late UiTree tree;

    setUp(() => tree = UiTree.parse(_fixture('folder_list_dump.xml')));

    test('finds the scrollable container', () {
      final scrollable = tree.firstScrollable;
      expect(scrollable, isNotNull);
      expect(scrollable!.scrollable, isTrue);
      expect(scrollable.shortClass, 'ScrollView');
    });

    test('scrollableAt picks the scrollable under a point', () {
      final scrollable = tree.firstScrollable!;
      final hit = tree.scrollableAt(
        scrollable.bounds.centreX,
        scrollable.bounds.centreY,
      );
      expect(hit?.index, scrollable.index);
    });

    test('scrollableAt returns null outside every scrollable', () {
      expect(tree.scrollableAt(-5, -5), isNull);
    });

    test('a row deep inside the list resolves to a clickable ancestor', () {
      final row =
          tree.nodes.firstWhere((n) => n.contentDesc.startsWith('Injury notes'));
      expect(tree.clickableSelfOrAncestor(row), isNotNull);
    });
  });

  group('UiTree.parse failure modes', () {
    test('rejects output with no XML at all', () {
      expect(
        () => UiTree.parse('ERROR: could not get idle state.'),
        throwsA(isA<DeviceFailure>()),
      );
    });

    test('skips the uiautomator banner before the declaration', () {
      final banner = 'UI hierchary dumped to: /dev/tty\n'
          '${_fixture('folder_root_dump.xml')}';
      expect(UiTree.parse(banner).nodes, isNotEmpty);
    });

    test('rejects truncated XML', () {
      expect(
        () => UiTree.parse('<?xml version="1.0"?><hierarchy><node bounds="[0,0]'),
        throwsA(isA<DeviceFailure>()),
      );
    });
  });

  group('foregroundPackage', () {
    test('is the app on every ANTA dump captured from the device', () {
      for (final name in const [
        'folder_root_dump.xml',
        'folder_list_dump.xml',
        'search_results_dump.xml',
      ]) {
        expect(
          UiTree.parse(_fixture(name)).foregroundPackage,
          'com.alexzamfir.anta',
          reason: name,
        );
      }
    });

    test('is the launcher when the app is not on screen', () {
      expect(
        UiTree.parse(_fixture('launcher_dump.xml')).foregroundPackage,
        'com.google.android.apps.nexuslauncher',
      );
    });

    test('an empty tree has no foreground package', () {
      expect(const UiTree([]).foregroundPackage, isNull);
    });

    test('system chrome never wins the top-level vote', () {
      final tree = UiTree.parse(
        '<?xml version="1.0"?><hierarchy rotation="0">'
        '<node class="android.widget.FrameLayout" package="com.android.systemui" '
        'bounds="[0,0][1280,2856]"/>'
        '<node class="android.widget.FrameLayout" package="com.foo.bar" '
        'bounds="[0,0][1280,300]"/>'
        '</hierarchy>',
      );
      expect(tree.foregroundPackage, 'com.foo.bar');
    });

    test('falls back to the commonest package when nothing is top level', () {
      final tree = UiTree.parse(
        '<?xml version="1.0"?><hierarchy rotation="0">'
        '<node class="a" package="android" bounds="[0,0][10,10]">'
        '<node class="b" package="com.foo.bar" bounds="[0,0][5,5]"/>'
        '<node class="c" package="com.foo.bar" bounds="[0,0][4,4]"/>'
        '<node class="d" package="com.other" bounds="[0,0][3,3]"/>'
        '</node></hierarchy>',
      );
      expect(tree.foregroundPackage, 'com.foo.bar');
    });
  });

  group('interestingLabels', () {
    test('lists the real labels of the folder root, in tree order', () {
      final labels = UiTree.parse(_fixture('folder_root_dump.xml'))
          .interestingLabels();
      expect(labels, contains('Search all notes'));
      expect(labels.indexOf('Search all notes'),
          lessThan(labels.indexOf('New folder')));
    });

    test('id-only nodes come after every labelled one', () {
      final labels = UiTree.parse(_fixture('folder_root_dump.xml'))
          .interestingLabels();
      final firstId = labels.indexWhere((l) => l.startsWith('id:'));
      if (firstId == -1) return;
      expect(
        labels.sublist(firstId).every((l) => l.startsWith('id:')),
        isTrue,
      );
    });

    test('a multi-line label is flattened with a separator', () {
      final labels = UiTree.parse(_fixture('folder_root_dump.xml'))
          .interestingLabels();
      expect(labels.any((l) => l.contains(' / ')), isTrue);
      expect(labels.every((l) => !l.contains('\n')), isTrue);
    });

    test('honours the limit and the clip', () {
      final labels = UiTree.parse(_fixture('launcher_dump.xml'))
          .interestingLabels(limit: 5, clip: 8);
      expect(labels, hasLength(5));
      expect(labels.every((l) => l.length <= 8), isTrue);
    });

    test('never repeats a label', () {
      final labels = UiTree.parse(_fixture('folder_list_dump.xml'))
          .interestingLabels(limit: 100);
      expect(labels.toSet(), hasLength(labels.length));
    });
  });
}
