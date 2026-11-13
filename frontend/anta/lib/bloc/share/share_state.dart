import 'package:equatable/equatable.dart';

import '../../models/share_overview.dart';
import '../../models/share_settings.dart';
import '../../services/share_service.dart';

/// The page's act an outcome answers, so it words the snackbar.
enum ShareAct { categoriesSet, eventUnshared, stopAll, undo }

/// Why an act wrote nothing.
enum ShareFailure {
  /// The database was no longer [ShareReady] when the write was asked for.
  refused,

  /// The write threw.
  failed,
}

/// What the last act did, for its snackbar. [sequence] is new for every
/// act, so two equal outcomes in a row still reach a listener that fires
/// on its change.
class ShareOutcome extends Equatable {
  final int sequence;
  final ShareAct act;

  /// What was written, for the words and the Undo; [ShareChange.none] for
  /// [ShareAct.stopAll] and for a failure.
  final ShareChange change;

  /// The marks [ShareAct.stopAll] cleared.
  final int cleared;

  final ShareFailure? failure;

  const ShareOutcome({
    required this.sequence,
    required this.act,
    this.change = ShareChange.none,
    this.cleared = 0,
    this.failure,
  });

  @override
  List<Object?> get props => [sequence, act, change, cleared, failure];
}

sealed class ShareState extends Equatable {
  const ShareState();

  @override
  List<Object?> get props => [];
}

final class ShareInitial extends ShareState {
  const ShareInitial();
}

/// The first load threw: the page says so in one line rather than stand
/// blank. A load that fails after one succeeded keeps what was shown.
final class ShareLoadFailed extends ShareState {
  const ShareLoadFailed();
}

final class ShareLoaded extends ShareState {
  final ShareAvailability availability;
  final ShareOverview overview;

  /// The receiver's two looks as stored, read with the overview while
  /// paired; the shipped values otherwise, read from nowhere.
  final ShareLook look;

  /// What may ring for a partner's event, on the same terms as [look].
  final ShareAlerts alerts;

  /// The last act's, kept across the reloads after it.
  final ShareOutcome? outcome;

  const ShareLoaded({
    required this.availability,
    required this.overview,
    this.look = const ShareLook(),
    this.alerts = ShareAlerts.own,
    this.outcome,
  });

  /// This state with what a receiver's setting write in flight will have
  /// stored — the only fields such a write can change.
  ShareLoaded copyWith({
    ShareOverview? overview,
    ShareLook? look,
    ShareAlerts? alerts,
  }) => ShareLoaded(
    availability: availability,
    overview: overview ?? this.overview,
    look: look ?? this.look,
    alerts: alerts ?? this.alerts,
    outcome: outcome,
  );

  @override
  List<Object?> get props => [availability, overview, look, alerts, outcome];
}
