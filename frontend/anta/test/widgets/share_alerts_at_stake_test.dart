import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/pairing/pairing_bloc.dart';
import 'package:anta/bloc/share/share_bloc.dart';
import 'package:anta/constants/sync_limits.dart';
import 'package:anta/services/share_service.dart';
import 'package:anta/widgets/share_alerts_at_stake.dart';

import '../services/pairing_support.dart';
import '../support/fake_share_service.dart';

/// Takes the pairing state a case shows it, as a pairing still loading at
/// the tap does when its answer lands.
class _ShownPairingBloc extends PairingBloc {
  _ShownPairingBloc({required super.authService, required super.gateway});

  void show(PairingState state) => emit(state);
}

/// The wait behind a confirmation that takes my alerts on the partner's
/// events off this phone (`docs/cloud-share-surfaces-roadmap.md` D30): it
/// has ONE deadline, counted from the tap, however its two reads — the
/// pairing's first state, then the armed count — share it.
void main() {
  late _ShownPairingBloc pairing;
  late ShareBloc share;
  late BuildContext page;

  /// The share service, which does not answer while a case runs: the armed
  /// count is never read.
  late Completer<ShareService> gate;

  // Built and closed outside the cases: a bloc closed from inside a widget
  // test's fake clock never finishes closing.
  setUp(() {
    gate = Completer<ShareService>();
    pairing = _ShownPairingBloc(
      authService: FakeAuthService(user: userA),
      gateway: FakePairingGateway(),
    );
    share = ShareBloc(
      service: () => gate.future,
      calendarChanges: const Stream<Object?>.empty(),
    );
  });

  tearDown(() async {
    // A bloc waits for the handler it is in: let the count answer first.
    if (!gate.isCompleted) gate.complete(FakeShareService());
    await share.close();
    await pairing.close();
  });

  Future<void> pumpPage(WidgetTester tester) => tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<PairingBloc>.value(value: pairing),
        BlocProvider<ShareBloc>.value(value: share),
      ],
      child: Builder(
        builder: (context) {
          page = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );

  /// Asks as a confirmation's tap does, and holds the answer once it lands.
  List<ArmedOnPartner> ask() {
    final answers = <ArmedOnPartner>[];
    unawaited(
      Future<ArmedOnPartner>.sync(
        () => alertsArmedOnPartner(page),
      ).then(answers.add),
    );
    return answers;
  }

  const bound = SyncLimits.stopConfirmShareRead;
  const noneArmed = (armed: false, partnerName: null);

  testWidgets('a tap while the pairing loads waits one bound in all, however '
      'late the pairing answers', (tester) async {
    await pumpPage(tester);
    expect(pairing.state, isA<PairingInitial>());

    final answers = ask();

    // The pairing answers late, with most of the bound spent.
    await tester.pump(bound * 0.9);
    expect(answers, isEmpty);
    pairing.show(const PairingPaired());
    await tester.pump();
    expect(answers, isEmpty, reason: 'the armed count has not answered');

    // The rest of the one bound, not a second one for the count.
    await tester.pump(bound * 0.1 + const Duration(milliseconds: 1));
    expect(answers, [noneArmed]);

    // The count's own clock, started when the pairing answered, runs out.
    await tester.pump(bound);
  });

  testWidgets('a pairing already loaded gives the count the whole bound', (
    tester,
  ) async {
    await pumpPage(tester);
    pairing.show(const PairingPaired());
    await tester.pump();

    final answers = ask();

    await tester.pump(bound - const Duration(milliseconds: 1));
    expect(answers, isEmpty);
    await tester.pump(const Duration(milliseconds: 2));
    expect(answers, [noneArmed]);
  });

  testWidgets('an account that is not paired answers at once and asks the '
      'share bloc nothing', (tester) async {
    await pumpPage(tester);
    pairing.show(const PairingUnpaired());
    await tester.pump();

    expect(alertsArmedOnPartner(page), noneArmed);
  });
}
