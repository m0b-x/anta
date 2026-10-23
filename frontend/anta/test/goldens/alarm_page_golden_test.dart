@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/pages/alarm_page.dart';

import '../widgets/support/alarm_page_fakes.dart';
import '../widgets/support/alarm_page_robot.dart';
import '../widgets/support/layout_errors.dart';
import 'support/golden_matrix.dart';

/// The ring screen with everything on it — the layout matrix's "fullest"
/// payload in `test/widgets/alarm_page_test.dart`: a re-ring of a removable
/// event, a title that wraps, a time span and a cut description. The payload
/// carries its own due instant, so nothing on the page reads the clock.
void main() {
  AlertPayload fullest() => AlertPayload(
    database: 'gym_notes',
    eventId: 'e1',
    alertId: 'a1',
    dayUtcMs: DateTime.utc(2026, 9, 20).millisecondsSinceEpoch,
    osId: 4242,
    mode: AlertMode.ring,
    title: 'Leg day - heavy squats and accessory work',
    timeLabel: '07:00',
    categoryId: 'gym',
    removeAfterAlert: true,
    snooze: true,
    snoozeMinutes: 10,
    fireAtMs: DateTime(2026, 9, 20, 7).millisecondsSinceEpoch,
    reRing: false,
    whenLabel: '07:00 – 08:30',
    excerpt:
        'Bring the belt and the chalk. Warm up on the bike first, then two '
        'light sets before the first working one.',
  );

  for (final cell in goldenCells) {
    testWidgets('alarm page, ${cell.label}', (tester) async {
      setGoldenSurface(tester, cell);
      // A status bar and a gesture bar, as the page's own suite draws every
      // phone: both insets are what its bottom clearance is made of.
      tester.view.viewPadding = const FakeViewPadding(
        top: AlarmPageRobot.systemBar,
        bottom: AlarmPageRobot.systemBar,
      );
      tester.view.padding = const FakeViewPadding(
        top: AlarmPageRobot.systemBar,
        bottom: AlarmPageRobot.systemBar,
      );
      final controller = ScriptedRingController(fullest(), active: 'gym_notes');
      addTearDown(controller.dispose);

      final errors = await layoutErrorsDuring(() async {
        await tester.pumpWidget(
          goldenApp(
            cell,
            home: AlarmPage(
              payload: controller.payload,
              controller: controller,
            ),
          ),
        );
        // Fixed frames rather than a settle: a ringing page may animate for
        // as long as it rings. The database resolves a turn after the first
        // build, and the remove row waits for it.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
      });

      expect(errors, isEmpty);
      await expectGolden('alarm_page', cell);
    });
  }
}
