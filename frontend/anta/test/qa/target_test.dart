import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/target.dart';
import '../../tool/qa/src/ui_tree.dart';

UiTree _tree(String name) =>
    UiTree.parse(File('test/qa/fixtures/$name').readAsStringSync());

void main() {
  late UiTree root;
  late TargetResolver resolver;

  setUp(() {
    root = _tree('folder_root_dump.xml');
    resolver = TargetResolver(root);
  });

  group('forms', () {
    test('#index picks the flat node', () {
      final node = root.nodes[5];
      final resolved = resolver.resolve('#${node.index}');
      expect(resolved.node?.index, node.index);
      expect(resolved.x, node.bounds.centreX);
      expect(resolved.y, node.bounds.centreY);
    });

    test('#index out of range is a target failure', () {
      expect(() => resolver.resolve('#9999'), throwsA(isA<TargetFailure>()));
    });

    test('x,y is taken literally and has no node', () {
      final resolved = resolver.resolve('640,1200');
      expect(resolved.x, 640);
      expect(resolved.y, 1200);
      expect(resolved.node, isNull);
    });

    test('x , y tolerates spaces and negatives', () {
      final resolved = resolver.resolve('-10 , 20');
      expect(resolved.x, -10);
      expect(resolved.y, 20);
    });

    test('id: matches a resource id, long or short', () {
      final full = resolver.resolve('id:android:id/content');
      final short = resolver.resolve('id:content');
      expect(full.node?.index, short.node?.index);
    });

    test('id: with no match is a target failure', () {
      expect(() => resolver.resolve('id:nope'), throwsA(isA<TargetFailure>()));
    });

    test('an empty target is a usage failure', () {
      expect(() => resolver.resolve('   '), throwsA(isA<UsageFailure>()));
    });
  });

  group('label precedence', () {
    test('exact content description wins', () {
      final resolved = resolver.resolve('Search all notes');
      expect(resolved.node?.contentDesc, 'Search all notes');
      expect(resolved.node?.clickable, isTrue);
    });

    test('case-insensitive is the second pass', () {
      final matches = resolver.matchLabel('search all notes');
      expect(matches.single.pass, MatchPass.caseInsensitive);
      expect(matches.single.field, MatchField.contentDesc);
    });

    test('substring is the last pass', () {
      final matches = resolver.matchLabel('navigation');
      expect(matches.single.pass, MatchPass.substring);
      expect(matches.single.node.contentDesc, 'Open navigation menu');
    });

    test('an exact match beats a substring match elsewhere', () {
      final matches = resolver.matchLabel('Recent');
      expect(matches.first.pass, MatchPass.exact);
      expect(matches.first.node.contentDesc, 'Recent');
    });

    test('content description is checked before text', () {
      final search = _tree('search_results_dump.xml');
      final matches = TargetResolver(search).matchLabel('squat');
      expect(matches.first.field, MatchField.text);
      expect(matches.first.node.text, 'squat');
    });

    test('no match at all is a target failure naming the target', () {
      expect(
        () => resolver.resolve('Nothing like this'),
        throwsA(isA<TargetFailure>().having(
            (e) => e.message, 'message', contains('Nothing like this'))),
      );
    });
  });

  group('ambiguity', () {
    late TargetResolver ambiguous;

    setUp(() {
      final nodes = <UiNode>[
        _node(0, desc: 'Delete'),
        _node(1, desc: 'Delete folder'),
        _node(2, text: 'Delete note'),
      ];
      ambiguous = TargetResolver(UiTree(nodes));
    });

    test('an exact hit is not ambiguous even with substring neighbours', () {
      expect(ambiguous.resolve('Delete').node?.index, 0);
    });

    test('several substring matches error and list the candidates', () {
      expect(
        () => ambiguous.resolve('elete'),
        throwsA(isA<TargetFailure>()
            .having((e) => e.message, 'message', contains('ambiguous'))
            .having((e) => e.message, 'message', contains('3 matches'))
            .having((e) => e.message, 'message', contains('--nth 0'))
            .having((e) => e.message, 'message', contains('--nth 2'))),
      );
    });

    test('--nth selects among the matches, 0-based', () {
      expect(ambiguous.resolve('elete', nth: 0).node?.index, 0);
      expect(ambiguous.resolve('elete', nth: 1).node?.index, 1);
      expect(ambiguous.resolve('elete', nth: 2).node?.index, 2);
    });

    test('content descriptions are listed before texts', () {
      final matches = ambiguous.matchLabel('elete');
      expect(matches.map((m) => m.field), [
        MatchField.contentDesc,
        MatchField.contentDesc,
        MatchField.text,
      ]);
    });

    test('--nth out of range is a target failure', () {
      expect(
        () => ambiguous.resolve('elete', nth: 7),
        throwsA(isA<TargetFailure>()
            .having((e) => e.message, 'message', contains('out of range'))),
      );
    });

    test('the exit code carried by a target failure is 2', () {
      expect(
        () => ambiguous.resolve('elete', nth: 7),
        throwsA(isA<TargetFailure>().having((e) => e.code, 'code', exitTarget)),
      );
    });

    test('a target string is trimmed before it is matched', () {
      expect(ambiguous.resolve('  Delete  ').node?.index, 0);
    });
  });
}

UiNode _node(int index, {String desc = '', String text = ''}) => UiNode(
      index: index,
      parentIndex: -1,
      depth: 0,
      className: 'android.view.View',
      text: text,
      contentDesc: desc,
      resourceId: '',
      packageName: 'com.alexzamfir.anta',
      bounds: UiRect(0, index * 100, 100, index * 100 + 100),
      clickable: true,
      longClickable: false,
      enabled: true,
      focused: false,
      focusable: true,
      checked: false,
      checkable: false,
      selected: false,
      scrollable: false,
    );
