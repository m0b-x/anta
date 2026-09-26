import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/core/qa/qa_overrides.dart';

void main() {
  tearDown(() => QaOverrides.textScale.value = null);

  Widget host() => const MaterialApp(
    home: QaTextScale(
      child: Scaffold(body: Center(child: Text('scaled'))),
    ),
  );

  double scaleOf(WidgetTester tester) => MediaQuery.textScalerOf(
    tester.element(find.text('scaled')),
  ).scale(10);

  testWidgets('passes the platform scale through while no override is set', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    expect(scaleOf(tester), 10);
  });

  testWidgets('imposes the override and follows changes without a rebuild', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    QaOverrides.textScale.value = 2.0;
    await tester.pump();
    expect(scaleOf(tester), 20);
    QaOverrides.textScale.value = 1.3;
    await tester.pump();
    expect(scaleOf(tester), 13);
    QaOverrides.textScale.value = null;
    await tester.pump();
    expect(scaleOf(tester), 10);
  });
}
