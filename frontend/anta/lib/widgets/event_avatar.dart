import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/form_metrics.dart';
import '../constants/row_metrics.dart';
import '../l10n/app_localizations.dart';
import '../models/app_user.dart';
import '../models/partner_look.dart';
import '../utils/marker_contrast.dart';
import 'user_avatar.dart';

class EventAvatar extends StatelessWidget {
  static const double radius = 20;
  static const double iconSize = 24;
  static const double backgroundAlpha = 0.16;

  /// The badge's centre from the avatar box's top and start edges: on the
  /// rim at 45°, bottom-end, so the sign never takes width from the title.
  static const double badgeCentre = radius + radius * math.sqrt1_2;

  /// The badge's outer disc, its halo included.
  static const double badgeDiameter =
      2 * (RowMetrics.partnerAvatarRadius + RowMetrics.shareBadgeHalo);

  final IconData icon;
  final Color color;

  /// Drawn as a ring in [color] with no fill — a partner's event under the
  /// Outlined look. The ring and the icon take the graphics floor against
  /// `rowGroup`, the ground every list draws the avatar on.
  final bool outlined;

  /// Whose the event is, as a corner badge that overhangs the 40 dp box
  /// without changing it.
  final EventAvatarBadge? badge;

  /// What the avatar says, read first in its row's one node — "From Maria";
  /// null keeps it silent, as every avatar was before sharing.
  final String? semanticsLabel;

  const EventAvatar({
    super.key,
    required this.icon,
    required this.color,
    this.outlined = false,
    this.badge,
    this.semanticsLabel,
  });

  /// The avatar of an event's row: [partner] is the surface's look when the
  /// event is a partner's, [mine] the same look when it is one of mine that
  /// I share; both null for my own unshared event — today's avatar,
  /// unchanged. A [mine] look that found no partner draws that avatar too:
  /// a mark shared with nobody says nothing.
  factory EventAvatar.ofRow({
    Key? key,
    required IconData icon,
    required Color color,
    required PartnerLook? partner,
    required AppLocalizations l10n,
    PartnerLook? mine,
  }) {
    if (mine != null && mine.unpaired) mine = null;
    return EventAvatar(
      key: key,
      icon: icon,
      color: color,
      outlined: partner?.outlined ?? false,
      badge: partner != null && partner.avatar
          ? EventAvatarBadge.partner(partner.partner)
          : partner == null && (mine?.markMine ?? false)
          ? EventAvatarBadge.mine
          : null,
      semanticsLabel: partner?.label(l10n) ?? mine?.mineLabel(l10n),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget visual;
    if (outlined) {
      final ink = MarkerContrast.atLeast(
        color,
        Theme.of(context).colorScheme.rowGroup,
      );
      visual = SizedBox.square(
        dimension: radius * 2,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: ink,
              width: FormMetrics.shareOutlineWidth,
            ),
          ),
          child: Center(
            child: Icon(icon, size: iconSize, color: ink),
          ),
        ),
      );
    } else {
      visual = CircleAvatar(
        radius: radius,
        backgroundColor: color.withValues(alpha: backgroundAlpha),
        foregroundColor: color,
        child: Icon(icon, size: iconSize),
      );
    }
    final sign = badge;
    if (sign != null) {
      visual = SizedBox.square(
        dimension: radius * 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            visual,
            PositionedDirectional(
              start: badgeCentre - badgeDiameter / 2,
              top: badgeCentre - badgeDiameter / 2,
              width: badgeDiameter,
              height: badgeDiameter,
              child: _Badge(sign),
            ),
          ],
        ),
      );
    }
    final label = semanticsLabel;
    if (label == null) return ExcludeSemantics(child: visual);
    return Semantics(
      label: label,
      child: ExcludeSemantics(child: visual),
    );
  }
}

/// Whose an event is, worn on its avatar's rim: the partner's face on a
/// partner's event under the Avatar look, or the share sign on an event I
/// share. One slot for both, since an event is never both.
@immutable
class EventAvatarBadge {
  /// The partner whose face the badge draws; null draws the person glyph.
  final AppUser? partner;

  /// Whether this is the sign on an event I share rather than a face.
  final bool isMine;

  const EventAvatarBadge.partner(this.partner) : isMine = false;

  const EventAvatarBadge._mine() : partner = null, isMine = true;

  /// The sign on an event I share.
  static const EventAvatarBadge mine = EventAvatarBadge._mine();

  /// Stands in for a partner whose profile was not read: `UserAvatar` then
  /// draws its person glyph.
  static const AppUser _faceless = AppUser(uid: '');

  @override
  bool operator ==(Object other) =>
      other is EventAvatarBadge &&
      other.partner == partner &&
      other.isMine == isMine;

  @override
  int get hashCode => Object.hash(partner, isMine);
}

class _Badge extends StatelessWidget {
  final EventAvatarBadge badge;

  const _Badge(this.badge);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.rowGroup,
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: const EdgeInsets.all(RowMetrics.shareBadgeHalo),
        child: badge.isMine
            ? CircleAvatar(
                radius: RowMetrics.partnerAvatarRadius,
                backgroundColor: colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.group_rounded,
                  size: RowMetrics.shareMarkSize,
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            : UserAvatar(
                user: badge.partner ?? EventAvatarBadge._faceless,
                radius: RowMetrics.partnerAvatarRadius,
              ),
      ),
    );
  }
}
