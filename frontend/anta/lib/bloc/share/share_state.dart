import 'package:equatable/equatable.dart';

import '../../models/share_overview.dart';
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

  /// The last act's, kept across the reloads after it.
  final ShareOutcome? outcome;

  const ShareLoaded({
    required this.availability,
    required this.overview,
    this.outcome,
  });

  @override
  List<Object?> get props => [availability, overview, outcome];
}
