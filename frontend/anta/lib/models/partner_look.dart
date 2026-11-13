import 'package:equatable/equatable.dart';

import '../l10n/app_localizations.dart';
import '../utils/share_copy.dart';
import 'app_user.dart';
import 'share_settings.dart';

/// How one surface draws a partner's event: the look this phone picked and
/// who the partner is (`docs/cloud-share-surfaces-roadmap.md` §6.7). Built
/// once by the page from its settings and the share availability it read,
/// and handed down to the rows like `CalendarAppearance` — never looked up
/// per row.
class PartnerLook extends Equatable {
  final ShareEventLook look;

  /// How a partner's folders and notes are drawn (`shareNoteLook`): the
  /// browser builds this from its page state as the calendar does from its
  /// own, and the calendar leaves it at the shipped value.
  final ShareNoteLook noteLook;

  /// The partner the Avatar look's badge draws; null while the audience is
  /// unread, and the badge then draws the person glyph.
  final AppUser? partner;

  /// The name the partner published, or null — the copy then says the
  /// localized stand-in.
  final String? name;

  /// Whether my own shared events wear the share sign (`shareMarkMine`).
  /// Their rows say "Shared with {name}" whatever it says.
  final bool markMine;

  /// The page's partner read found no one: a pair that ended, whose marks
  /// the shared reader clears at its next look. Until then my rows wear no
  /// share sign and say nothing of sharing — there is nobody to share with.
  final bool unpaired;

  const PartnerLook({
    this.look = ShareEventLook.outlined,
    this.noteLook = ShareNoteLook.avatar,
    this.partner,
    this.name,
    this.markMine = true,
    this.unpaired = false,
  });

  /// Whether a partner's event is drawn by its outline.
  bool get outlined => look == ShareEventLook.outlined;

  /// Whether a partner's event wears the partner's face.
  bool get avatar => look == ShareEventLook.avatar;

  /// Whether a partner's folder or note wears the partner's face.
  bool get noteAvatar => noteLook == ShareNoteLook.avatar;

  /// "From {name}": read first on a partner's row in every look, the plain
  /// one included, since nothing else on that row says whose it is.
  String label(AppLocalizations l10n) =>
      l10n.shareMarkPartnerLabel(ShareCopy.partnerName(l10n, name));

  /// "Shared with {name}": read first on a row of mine that I share, with
  /// or without the sign.
  String mineLabel(AppLocalizations l10n) =>
      l10n.shareMarkMineLabel(ShareCopy.partnerName(l10n, name));

  @override
  List<Object?> get props => [
    look,
    noteLook,
    partner,
    name,
    markMine,
    unpaired,
  ];
}
