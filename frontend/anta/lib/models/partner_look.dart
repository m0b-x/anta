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

  /// The partner the Avatar look's badge draws; null while the audience is
  /// unread, and the badge then draws the person glyph.
  final AppUser? partner;

  /// The name the partner published, or null — the copy then says the
  /// localized stand-in.
  final String? name;

  const PartnerLook({
    this.look = ShareEventLook.outlined,
    this.partner,
    this.name,
  });

  /// Whether a partner's event is drawn by its outline.
  bool get outlined => look == ShareEventLook.outlined;

  /// Whether a partner's event wears the partner's face.
  bool get avatar => look == ShareEventLook.avatar;

  /// "From {name}": read first on a partner's row in every look, the plain
  /// one included, since nothing else on that row says whose it is.
  String label(AppLocalizations l10n) =>
      l10n.shareMarkPartnerLabel(ShareCopy.partnerName(l10n, name));

  @override
  List<Object?> get props => [look, partner, name];
}
