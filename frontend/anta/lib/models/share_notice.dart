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
/// armed on them: the alert is off now, and the person is told (D23).
final class ShareLeftWithAlert extends ShareNotice {
  final List<ShareNoticeEvent> events;

  const ShareLeftWithAlert(this.events);

  @override
  List<Object?> get props => [events];
}
