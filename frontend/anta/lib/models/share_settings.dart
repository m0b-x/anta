import 'package:equatable/equatable.dart';

import 'calendar_event.dart';

/// How a partner's event is drawn on this phone
/// (`docs/cloud-share-surfaces-roadmap.md` §6.7, D12).
enum ShareEventLook {
  /// The event's own colour as an outline rather than a fill.
  outlined,

  /// Drawn as my own, with the partner's avatar beside it.
  avatar,

  /// Drawn exactly as my own.
  plain;

  /// Forward-compatible parsing: unknown or null falls back to [outlined].
  static ShareEventLook fromName(String? name) {
    for (final look in values) {
      if (look.name == name) return look;
    }
    return outlined;
  }
}

/// What may ring for an event a partner shares (§6.8, D13). Per device: the
/// partner's alerts never reach this phone, so every alert on a shared event
/// is a row of my own.
enum ShareAlerts {
  /// Nothing shared rings; my alert rows on shared events stay, unarmed.
  off,

  /// Only the alerts I added to a shared event myself.
  own,

  /// Those, plus my category's alerts on the shared events of its id.
  category;

  /// Forward-compatible parsing: unknown or null falls back to [own], the
  /// one that arms only what I asked for on that event.
  static ShareAlerts fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return own;
  }

  /// Whether [event]'s category alerts reach it on this phone, or null when
  /// nothing of it may arm — the one predicate the scheduler plans by and the
  /// badges answer by, so a badge never promises what will not ring.
  ///
  /// My own events keep their own switch, exactly as before sharing. A
  /// partner's event follows this setting alone: its "Category alerts"
  /// switch is the partner's and is not read.
  bool? inheritsOn(CalendarEvent event) {
    if (!event.fromPartner) return event.categoryAlerts;
    return switch (this) {
      off => null,
      own => false,
      category => true,
    };
  }
}

/// The two settings a calendar surface draws shared rows by, read with the
/// rest of the page's settings and handed down like `CalendarAppearance` —
/// never looked up per row.
class ShareLook extends Equatable {
  final ShareEventLook eventLook;

  /// Whether my own shared rows carry their mark.
  final bool markMine;

  const ShareLook({
    this.eventLook = ShareEventLook.outlined,
    this.markMine = true,
  });

  @override
  List<Object?> get props => [eventLook, markMine];
}
