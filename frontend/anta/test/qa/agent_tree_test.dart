import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/agent_protocol.dart';
import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/target.dart';
import '../../tool/qa/src/ui_tree.dart';

Map<String, Object?> _node(
  int index, {
  int parent = 0,
  int depth = 1,
  String label = '',
  String value = '',
  String hint = '',
  String tooltip = '',
  String id = '',
  List<int> rect = const [0, 0, 100, 100],
  List<String> flags = const [],
}) =>
    {
      AgentNodeKeys.index: index,
      AgentNodeKeys.parent: parent,
      AgentNodeKeys.depth: depth,
      AgentNodeKeys.label: label,
      AgentNodeKeys.value: value,
      AgentNodeKeys.hint: hint,
      AgentNodeKeys.tooltip: tooltip,
      AgentNodeKeys.identifier: id,
      AgentNodeKeys.rect: rect,
      AgentNodeKeys.flags: flags,
    };

String _dump(List<Map<String, Object?>> nodes) => jsonEncode({
      AgentKeys.ok: true,
      AgentKeys.dpr: 3.0,
      AgentKeys.width: 1320,
      AgentKeys.height: 2868,
      AgentKeys.nodes: [
        _node(0, parent: -1, depth: 0, rect: [0, 0, 1320, 2868]),
        ...nodes,
      ],
    });

void main() {
  group('UiTree.fromAgentJson', () {
    test('maps label, tooltip, value and identifier like the Android bridge', () {
      final tree = UiTree.fromAgentJson(
        _dump([
          _node(1, tooltip: 'Search all notes', id: 'search-open',
              rect: [992, 156, 1136, 300], flags: [AgentFlags.click, AgentFlags.button]),
          _node(2, label: 'All notes\n3', id: 'drawer-all-notes',
              rect: [0, 462, 1320, 609], flags: [AgentFlags.click]),
          _node(3, label: 'Query', value: 'squat', hint: 'Search',
              rect: [0, 0, 500, 80],
              flags: [AgentFlags.textField, AgentFlags.focused]),
        ]),
        appPackage: 'com.alexzamfir.anta',
      );
      expect(tree.source, UiTreeSource.agent);
      expect(tree.nodes, hasLength(4));
      final search = tree.byIndex(1)!;
      expect(search.contentDesc, 'Search all notes');
      expect(search.shortId, 'search-open');
      expect(search.shortClass, 'Button');
      expect(search.clickable, isTrue);
      expect(search.bounds.centreX, 1064);
      final row = tree.byIndex(2)!;
      expect(row.label, 'All notes\n3');
      expect(row.shortClass, 'View');
      final field = tree.byIndex(3)!;
      expect(field.shortClass, 'EditText');
      expect(field.text, 'squat');
      expect(field.hint, 'Search');
      expect(field.focused, isTrue);
      expect(field.describe(), contains('hint="Search"'));
      expect(tree.foregroundPackage, 'com.alexzamfir.anta');
    });

    test('a label and a tooltip that differ are joined the Android way', () {
      final tree = UiTree.fromAgentJson(
        _dump([_node(1, label: 'Inbox', tooltip: 'Open folder')]),
        appPackage: 'x',
      );
      expect(tree.byIndex(1)!.contentDesc, 'Inbox\nOpen folder');
    });

    test('hidden nodes stay in the tree but out of the interesting listing', () {
      final tree = UiTree.fromAgentJson(
        _dump([
          _node(1, label: 'Visible row', flags: [AgentFlags.click]),
          _node(2, label: 'Scrolled away',
              rect: [0, 3000, 1320, 3100], flags: [AgentFlags.click, AgentFlags.hidden]),
        ]),
        appPackage: 'x',
      );
      expect(tree.byIndex(2)!.hidden, isTrue);
      expect(tree.byIndex(2)!.interesting, isFalse);
      expect(tree.byIndex(2)!.flags, contains('hidden'));
      expect(tree.interestingLabels(), ['Visible row']);
      final resolved = TargetResolver(tree).resolve('Scrolled away');
      expect(resolved.node!.hidden, isTrue);
    });

    test('flags map onto the uiautomator vocabulary', () {
      final tree = UiTree.fromAgentJson(
        _dump([
          _node(1, label: 'Dark mode', flags: [
            AgentFlags.click,
            AgentFlags.checkable,
            AgentFlags.checked,
            AgentFlags.toggle,
          ]),
          _node(2, label: 'List', flags: [AgentFlags.scroll]),
          _node(3, label: 'Off', flags: [AgentFlags.disabled, AgentFlags.selected, AgentFlags.long]),
        ]),
        appPackage: 'x',
      );
      final toggle = tree.byIndex(1)!;
      expect(toggle.shortClass, 'Switch');
      expect(toggle.flags, 'click,checked');
      expect(tree.byIndex(2)!.scrollable, isTrue);
      expect(tree.firstScrollable!.index, 2);
      expect(tree.byIndex(2)!.shortClass, 'Scroll');
      final off = tree.byIndex(3)!;
      expect(off.enabled, isFalse);
      expect(off.selected, isTrue);
      expect(off.longClickable, isTrue);
      expect(off.flags, 'long,selected,disabled');
    });

    test('rejects a payload without nodes', () {
      expect(
        () => UiTree.fromAgentJson('{"ok": true}', appPackage: 'x'),
        throwsA(isA<DeviceFailure>()),
      );
      expect(
        () => UiTree.fromAgentJson('not json', appPackage: 'x'),
        throwsA(isA<DeviceFailure>()),
      );
    });
  });

  group('classForAgentFlags', () {
    test('picks the most specific role', () {
      expect(UiTree.classForAgentFlags({AgentFlags.textField, AgentFlags.click}), 'EditText');
      expect(UiTree.classForAgentFlags({AgentFlags.button}), 'Button');
      expect(UiTree.classForAgentFlags({AgentFlags.checkable}), 'CheckBox');
      expect(UiTree.classForAgentFlags({AgentFlags.header}), 'Header');
      expect(UiTree.classForAgentFlags({AgentFlags.image}), 'Image');
      expect(UiTree.classForAgentFlags({AgentFlags.link}), 'Link');
      expect(UiTree.classForAgentFlags({AgentFlags.slider}), 'Slider');
      expect(UiTree.classForAgentFlags(const {}), 'View');
    });
  });

  group('parseDumpText', () {
    test('detects the agent JSON and falls back to XML', () {
      final json = parseDumpText(_dump([_node(1, label: 'x')]), appPackage: 'pkg');
      expect(json.source, UiTreeSource.agent);
      const xml = '<?xml version="1.0"?><hierarchy rotation="0">'
          '<node index="0" text="" class="android.widget.FrameLayout" '
          'package="com.alexzamfir.anta" content-desc="" bounds="[0,0][100,100]" '
          'clickable="false" enabled="true" scrollable="false" /></hierarchy>';
      final tree = parseDumpText(xml, appPackage: 'pkg');
      expect(tree.source, UiTreeSource.uiautomator);
      expect(tree.foregroundPackage, 'com.alexzamfir.anta');
    });
  });
}
