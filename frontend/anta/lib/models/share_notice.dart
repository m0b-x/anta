import 'package:equatable/equatable.dart';

/// What the app tells a person once, inside the app, after a read of what
/// their partner shares changed what this phone holds
/// (`docs/cloud-share-surfaces-roadmap.md` §6.14). It names what happened;
/// the surface that says it chooses the words and the language.
sealed class ShareNotice extends Equatable {
  const ShareNotice();
}

/// A partner's event a notice names: by its id as well as its title, since
/// two events may share a title and each is one event to the person — the
/// surface counts and merges notices by [id], and words them by [title].
typedef ShareNoticeEvent = ({String id, String title});

/// Something this phone had not held arrived: a category the partner began
/// to share, or an event shared one by one.
final class ShareArrived extends ShareNotice {
  /// The partner's categories newly held — their own, and a built-in they
  /// began to share — by id: the surface resolves each to its label, a
  /// built-in's being this person's own.
  final List<String> categoryIds;

  /// The events newly shared one by one: never an event that came with one
  /// of [categoryIds], or with a category already shared.
  final List<ShareNoticeEvent> events;

  const ShareArrived({this.categoryIds = const [], this.events = const []});

  bool get isEmpty => categoryIds.isEmpty && events.isEmpty;

  @override
  List<Object?> get props => [categoryIds, events];
}

/// The partner's events that left this phone — un-shared, deleted, their
/// category un-shared, the pair ended — while an alert of this person's was
/// armed on them: the alert is off now, and the person is told (D23). Only
/// for the partner's act: what left by an act of the person's own — their
/// Unpair, Stop syncing, a restore — was said by its confirmation (D30).
final class ShareLeftWithAlert extends ShareNotice {
  final List<ShareNoticeEvent> events;

  /// The partner's name as it stood while the pair did, kept before the
  /// pair was forgotten (D35); null for an account with no name, and when
  /// it could not be read — the surface then says "your partner".
  final String? partnerName;

  const ShareLeftWithAlert(this.events, {this.partnerName});

  @override
  List<Object?> get props => [events, partnerName];
}

/// The person hid a partner's category on this phone while an alert of
/// theirs was armed on its events: those alerts are off until it shows
/// again (D30). Posted once the hide is written, whatever surface asked for
/// it is still up — the answer to the person's own tap, so said at once.
final class ShareHiddenWithAlerts extends ShareNotice {
  final String categoryId;

  /// The category's name as the catalogue held it at the tap, said when
  /// the surface cannot resolve [categoryId] any more; a built-in is said
  /// by the person's own label for it.
  final String name;

  const ShareHiddenWithAlerts({required this.categoryId, required this.name});

  @override
  List<Object?> get props => [categoryId, name];
}
