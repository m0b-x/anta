import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/pairing/pairing_bloc.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/pair_record.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/pairing_sheet.dart';

import '../database/support/db_test_support.dart';
import '../services/pairing_support.dart';

/// The pairing sheet over the real bloc, service and a fake gateway: what
/// the sheet does when the pair is made.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  tearDown(() {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    PairingService.reset();
  });

  testWidgets('closes itself once when the pair is made: "paired" arrives '
      'again when the partner\'s name does, and that second arrival must not '
      'close the page the sheet was opened from', (tester) async {
    final auth = FakeAuthService(user: userA);
    final gateway = FakePairingGateway();
    addTearDown(gateway.dispose);
    late PairingBloc bloc;
    await tester.runAsync(() async {
      DatabaseLifecycle.notifyDatabaseSwitching();
      SettingsService.reset();
      PairingService.reset();
      PairingService.forTesting(
        auth: auth,
        gateway: gateway,
        settings: SettingsService.forTesting(await openTestDatabase()),
      );
      bloc = PairingBloc(authService: auth, gateway: gateway)
        ..add(const LoadPairing());
      await pumpEventQueue();
    });
    addTearDown(() => bloc.close());

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    appBar: AppBar(title: const Text('Sync & sharing')),
                    body: TextButton(
                      onPressed: () => showPairingSheet(context, bloc),
                      child: const Text('pair'),
                    ),
                  ),
                ),
              ),
              child: const Text('open the page'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open the page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pair'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.pairingGenerate),
      findsOneWidget,
    );

    // The partner redeems a code of this account's: the first "paired".
    late PairRecord pair;
    await tester.runAsync(() async {
      bloc.add(const GenerateInviteRequested());
      await pumpEventQueue();
      pair = await gateway.createPair(
        self: PairProfile(uid: userB.uid),
        partner: PairProfile(uid: userA.uid),
        inviteCode: gateway.invites.keys.single,
      );
      await pumpEventQueue();
    });
    final first = bloc.state;
    expect(first, isA<PairingPaired>());
    // The sheet has begun to close and is still on screen, sliding away…
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.bySemanticsIdentifier(SemanticsIds.pairingCodeField),
      findsOneWidget,
    );
    // …when the partner's name arrives: "paired" again.
    await tester.runAsync(() async {
      await gateway.writeProfile(
        pairId: pair.pairId,
        profile: PairProfile(uid: userB.uid, displayName: 'Partner'),
      );
      await pumpEventQueue();
    });
    expect(bloc.state, isNot(first), reason: 'a second paired state');
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.pairingCodeField),
      findsNothing,
      reason: 'the sheet closed',
    );
    expect(
      find.text('Sync & sharing'),
      findsOneWidget,
      reason: 'the page under it did not',
    );
  });
}
