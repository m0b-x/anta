import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_driver/qa_agent.dart' show screenMoving;
import '../../tool/qa/src/agent_protocol.dart';

void main() {
  group('the agent settle', () {
    test('the cap is the measured 150 ms, and the agent is built from it', () {
      expect(agentSettleCapMs, 150);
      final protocol = File('tool/qa/src/agent_protocol.dart').readAsStringSync();
      final doc = protocol.substring(0, protocol.indexOf('const int agentSettleCapMs'));
      expect(doc.split(RegExp(r'\r?\n\r?\n')).last, contains('p50'),
          reason: 'the constant carries the measurement it was tuned from');
      final agent = File('test_driver/qa_agent.dart').readAsStringSync();
      expect(agent, contains('_settleCap = Duration(milliseconds: agentSettleCapMs)'));
    });

    testWidgets('a menu counts as moving from its pop until it is gone', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PopupMenuButton<int>(
            itemBuilder: (_) => const [PopupMenuItem(value: 1, child: Text('Newest'))],
            child: const Text('Order'),
          ),
        ),
      ));
      expect(screenMoving(), isFalse);

      await tester.tap(find.text('Order'));
      await tester.pumpAndSettle();
      expect(screenMoving(), isFalse, reason: 'an open menu is at rest');

      await tester.tap(find.text('Newest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(screenMoving(), isTrue);
      await tester.pumpAndSettle();
      expect(screenMoving(), isFalse);
    });

    testWidgets('a pager turning to a page counts as moving until it lands', (tester) async {
      final pages = PageController();
      addTearDown(pages.dispose);
      await tester.pumpWidget(MaterialApp(
        home: PageView(
          controller: pages,
          children: [for (var i = 0; i < 4; i++) Text('Page $i')],
        ),
      ));
      expect(screenMoving(), isFalse);

      pages.animateToPage(3, duration: const Duration(milliseconds: 300), curve: Curves.ease);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(screenMoving(), isTrue);
      await tester.pumpAndSettle();
      expect(screenMoving(), isFalse);
      expect(find.text('Page 3'), findsOneWidget);
    });
  });
}
