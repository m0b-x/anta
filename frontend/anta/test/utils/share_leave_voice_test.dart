import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/utils/share_leave_voice.dart';

/// One line for one leave of the partner's share: the page in front speaks,
/// a page of the same leave underneath closes without a line of its own,
/// and it speaks only when no page in front did.
void main() {
  testWidgets('the page in front speaks; the one underneath, offered first '
      'or after, stays silent', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final said = <String>[];

    ShareLeaveVoice.offer(() => said.add('folder'));
    ShareLeaveVoice.claim(() => said.add('note'));
    ShareLeaveVoice.claim(() => said.add('deeper folder'));
    await tester.pump();

    expect(said, ['note']);
  });

  testWidgets('a page underneath with nobody of the leave in front speaks '
      'after the frame, once', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final said = <String>[];

    ShareLeaveVoice.offer(() => said.add('outer'));
    ShareLeaveVoice.offer(() => said.add('inner'));
    expect(said, isEmpty);
    await tester.pump();

    expect(said, ['outer']);

    // The next leave is a leave of its own.
    ShareLeaveVoice.claim(() => said.add('next'));
    await tester.pump();
    expect(said, ['outer', 'next']);
  });
}
