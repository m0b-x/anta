import 'dart:async';

import 'package:equatable/equatable.dart';

import '../../models/share_overview.dart';
import '../../models/share_settings.dart';
import 'share_state.dart' show ShareFailure;

sealed class ShareEvent extends Equatable {
  const ShareEvent();

  @override
  List<Object?> get props => [];
}

/// The Sharing page opened: load what it lists, follow what changes it, and
/// ask for one shared read (D22).
final class ShareOpened extends ShareEvent {
  const ShareOpened();
}

/// A surface that only summarises what is shared — Sync & sharing — wants
/// the overview: loaded, with no shared read, which belongs to the Sharing
/// page's open alone (D22).
final class ShareLoadRequested extends ShareEvent {
  const ShareLoadRequested();
}

/// An intent that writes marks. Its write starts when it is added, and the
/// service writes them in that order; the bloc says their outcomes one at a
/// time, in the same order: two that overtook each other would leave the
/// older outcome on the page.
sealed class ShareActEvent extends ShareEvent {
  /// The surface that asked, handed back on the act's [ShareOutcome]: a
  /// list sheet answers for the acts it started and for no other — one
  /// dismissed with an act running and reopened at once must not take the
  /// old act's outcome for its own. Null for the page's own acts. Compared
  /// by identity, never part of [props].
  final Object? asker;

  /// How this act's failure is said when its bloc closed before saying it —
  /// the write failed once the bloc had gone, or before a handler the close
  /// kept from running (`ShareBloc.close`): on the app's messenger the
  /// surface captured (`shareFailurePastSurface`), since neither the bloc
  /// nor, often, the surface is left to say it. Null leaves the failure to
  /// the log. Never part of [props].
  final void Function(ShareFailure failure)? failedPastBloc;

  const ShareActEvent({this.asker, this.failedPastBloc});
}

/// The tick sheet's Done: what the person changed against the ticks the
/// sheet opened with — [shared] newly ticked, [unshared] un-ticked — and
/// nothing of the categories they left alone, whose marks may have moved
/// since the sheet read them (`ShareService.changeCategoriesShared`).
final class ShareCategoriesSet extends ShareActEvent {
  final Set<String> shared;
  final Set<String> unshared;

  const ShareCategoriesSet({
    this.shared = const {},
    this.unshared = const {},
    super.failedPastBloc,
  });

  @override
  List<Object?> get props => [shared, unshared];
}

/// A row's ✕ on the Single events sheet: the event's own mark taken away.
final class ShareEventUnshared extends ShareActEvent {
  final String eventId;

  const ShareEventUnshared(this.eventId, {super.asker, super.failedPastBloc});

  @override
  List<Object?> get props => [eventId];
}

/// "Share a folder" on the Folders sheet: the folder picked there shared,
/// with everything under it.
final class ShareFolderShared extends ShareActEvent {
  final String folderId;

  const ShareFolderShared(this.folderId, {super.asker, super.failedPastBloc});

  @override
  List<Object?> get props => [folderId];
}

/// A row's ✕ on the Folders sheet: the folder's mark taken away.
final class ShareFolderUnshared extends ShareActEvent {
  final String folderId;

  const ShareFolderUnshared(this.folderId, {super.asker, super.failedPastBloc});

  @override
  List<Object?> get props => [folderId];
}

/// "Stop sharing everything", confirmed.
final class ShareStopAllRequested extends ShareActEvent {
  const ShareStopAllRequested({super.failedPastBloc});
}

/// A snackbar's Undo of [change].
final class ShareUndoRequested extends ShareActEvent {
  final ShareChange change;

  const ShareUndoRequested(
    this.change, {
    super.asker,
    super.failedPastBloc,
  });

  @override
  List<Object?> get props => [change];
}

/// A switch under "{name} shares with you": the partner's category
/// [categoryId] — one of theirs, or a built-in they share — shown on this
/// phone or hidden (§6.4).
final class ShareCategoryShownSet extends ShareEvent {
  final String categoryId;
  final bool shown;

  const ShareCategoryShownSet(this.categoryId, {required this.shown});

  @override
  List<Object?> get props => [categoryId, shown];
}

/// A confirmation about to be asked of an act that ends what this phone
/// holds of the partner's (D30): [answer] completes with how many of their
/// events hold an armed alert of mine, 0 when that cannot be read. Never
/// added for an account that is not paired.
final class ShareArmedCountRequested extends ShareEvent {
  final Completer<int> answer;

  const ShareArmedCountRequested(this.answer);

  @override
  List<Object?> get props => [answer];
}

/// A partner's event about to be opened from a list (D33): [answer]
/// completes with whether this phone still holds [eventId] of theirs —
/// true when that cannot be read, so the tap is never left unanswered.
final class SharePartnerEventHeldRequested extends ShareEvent {
  final String eventId;
  final Completer<bool> answer;

  const SharePartnerEventHeldRequested(this.eventId, this.answer);

  @override
  List<Object?> get props => [eventId, answer];
}

/// How a partner's events are drawn on this phone (§6.7).
final class ShareEventLookSet extends ShareEvent {
  final ShareEventLook look;

  const ShareEventLookSet(this.look);

  @override
  List<Object?> get props => [look];
}

/// How a partner's folders and notes are drawn on this phone (§6.7, D12).
final class ShareNoteLookSet extends ShareEvent {
  final ShareNoteLook look;

  const ShareNoteLookSet(this.look);

  @override
  List<Object?> get props => [look];
}

/// Whether what I share carries its mark (§6.7, D10).
final class ShareMarkMineSet extends ShareEvent {
  final bool markMine;

  const ShareMarkMineSet(this.markMine);

  @override
  List<Object?> get props => [markMine];
}

/// What may ring for a partner's event (§6.8, D13).
final class ShareAlertsSet extends ShareEvent {
  final ShareAlerts alerts;

  const ShareAlertsSet(this.alerts);

  @override
  List<Object?> get props => [alerts];
}

/// Fed by the service's availability, the calendar's changes and the end of
/// each sync run, not the UI: a bind, a pairing that ended, a pull, a mark
/// written elsewhere, a share sent.
final class ShareSourcesChanged extends ShareEvent {
  const ShareSourcesChanged();
}
