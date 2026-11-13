import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/pairing/pairing_bloc.dart';
import '../bloc/share/share_bloc.dart';
import '../constants/sync_limits.dart';
import '../l10n/app_localizations.dart';
import '../utils/share_copy.dart';

/// Whether an alert of mine is armed on something the partner shares, and
/// the partner's name to say it with.
typedef ArmedOnPartner = ({bool armed, String? partnerName});

const ArmedOnPartner _noneArmed = (armed: false, partnerName: null);

/// Whether an alert of mine is armed on something the partner shares, asked
/// at the tap of a confirmation whose act takes it off this phone — Stop
/// syncing, Unpair, Delete cloud copy, Delete account — so the dialog can
/// say so before I confirm (`docs/cloud-share-surfaces-roadmap.md` D30).
///
/// Once the pairing has loaded, an account that is not paired answers at
/// once, reading and awaiting nothing and building no share bloc, so its
/// dialog is the one it always was. A tap before the pairing has loaded
/// waits for its first loaded state rather than read "not paired" off a
/// state that has not been asked yet. A paired account asks [ShareBloc].
/// The whole wait is bounded by [SyncLimits.stopConfirmShareRead], as D25's
/// read is: a read that fails or comes late answers "none armed", and the
/// dialog opens without the sentence rather than leave the tap unanswered.
FutureOr<ArmedOnPartner> alertsArmedOnPartner(BuildContext context) {
  final pairing = context.read<PairingBloc>();
  final state = pairing.state;
  if (!_loading(state)) {
    return state is PairingPaired ? _ask(context, state) : _noneArmed;
  }
  return pairing.stream
      .firstWhere((next) => !_loading(next))
      .then((loaded) {
        if (loaded is! PairingPaired || !context.mounted) {
          return Future.value(_noneArmed);
        }
        return _ask(context, loaded);
      })
      .timeout(SyncLimits.stopConfirmShareRead, onTimeout: () => _noneArmed)
      .then((answer) => answer, onError: (Object _) => _noneArmed);
}

/// The pairing has not answered yet: whether this account is paired is
/// not known.
bool _loading(PairingState state) =>
    state is PairingInitial || state is PairingLoading;

Future<ArmedOnPartner> _ask(BuildContext context, PairingPaired paired) {
  final share = context.read<ShareBloc>();
  if (share.isClosed) return Future.value(_noneArmed);
  final answer = Completer<int>();
  share.add(ShareArmedCountRequested(answer));
  return answer.future
      .timeout(SyncLimits.stopConfirmShareRead, onTimeout: () => 0)
      .then(
        (armed) => (armed: armed > 0, partnerName: paired.partner?.displayName),
        onError: (Object _) => _noneArmed,
      );
}

/// [body], followed by "Your alerts on what {name} shares turn off." while
/// [alertsArmedOnPartner] says so — at once, unchanged, for an account that
/// is not paired. Null when the tap waited and something opened over the
/// page meanwhile: the confirmation belongs to the page it was asked on.
FutureOr<String?> withAlertsTurnOffLine(
  BuildContext context,
  AppLocalizations l10n,
  String body,
) {
  final asked = alertsArmedOnPartner(context);
  if (asked is! Future<ArmedOnPartner>) return body;
  return asked.then((answer) {
    if (!context.mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return null;
    }
    if (!answer.armed) return body;
    final name = ShareCopy.partnerName(l10n, answer.partnerName);
    return '$body ${ShareCopy.sentence(l10n.shareAlertsTurnOffLine(name))}';
  });
}
