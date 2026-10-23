import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/sync/sync_suspension.dart';

void main() {
  test('nothing is suspended outside a scope', () {
    expect(SyncSuspension.isSuspended, isFalse);
  });

  test('a scope suspends for its body and returns its value', () async {
    final seen = await SyncSuspension.run(() async {
      return SyncSuspension.isSuspended;
    });

    expect(seen, isTrue);
    expect(SyncSuspension.isSuspended, isFalse);
  });

  test('nested scopes resume only when the outermost ends', () async {
    final seen = <bool>[];
    await SyncSuspension.run(() async {
      await SyncSuspension.run(() async {});
      seen.add(SyncSuspension.isSuspended);
    });

    expect(seen, [isTrue]);
    expect(SyncSuspension.isSuspended, isFalse);
  });

  test('a throwing body releases the scope', () async {
    await expectLater(
      SyncSuspension.run<void>(() async => throw StateError('boom')),
      throwsStateError,
    );

    expect(SyncSuspension.isSuspended, isFalse);
  });
}
