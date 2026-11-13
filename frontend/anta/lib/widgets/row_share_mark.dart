import 'package:flutter/material.dart';

import '../constants/row_metrics.dart';
import '../l10n/app_localizations.dart';
import '../models/app_user.dart';
import '../models/folder.dart';
import '../models/note_metadata.dart';
import '../models/partner_look.dart';
import 'user_avatar.dart';

/// Whose a browser row is, as the row draws and says it
/// (`docs/cloud-share-surfaces-roadmap.md` §6.7, §16.8): the sign on a
/// folder I share or the partner's face on a row of theirs — one slot, never
/// both — and the words read first on the row in every look, the plain one
/// included.
///
/// Resolved per build from the row's transient flags and the [PartnerLook]
/// its page handed down. Null without a look: a page hands none until it
/// holds a shared row, so the rows of an account that never paired build
/// the tree they always built.
final class RowShareMark {
  const RowShareMark._({required this.label, this.sign = false, this.face});

  /// "From {name}" on the partner's row, "Shared with {name}" on mine.
  final String label;

  /// Whether the row draws the sign on what I share (`shareMarkMine`).
  final bool sign;

  /// The partner whose face the row draws, under the Avatar look; null
  /// draws none. Faceless while the partner is unread: the person glyph.
  final AppUser? face;

  /// A folder row's mark: the partner's folder in every look, and a folder
  /// of mine shared by its own mark or a mark above it — a subfolder of a
  /// shared folder wears it too (§16.8 fa) — while there is a partner.
  static RowShareMark? forFolder(
    Folder folder,
    PartnerLook? look,
    AppLocalizations l10n,
  ) {
    if (look == null) return null;
    if (folder.fromPartner) return _theirs(look, l10n);
    if (!folder.share.isShared || look.unpaired) return null;
    return RowShareMark._(label: look.mineLabel(l10n), sign: look.markMine);
  }

  /// A note row's mark: the partner's note only — a note of mine in a
  /// shared folder is not marked; its folder is (§6.7).
  static RowShareMark? forNote(
    NoteMetadata note,
    PartnerLook? look,
    AppLocalizations l10n,
  ) {
    if (look == null || !note.fromPartner) return null;
    return _theirs(look, l10n);
  }

  static RowShareMark _theirs(PartnerLook look, AppLocalizations l10n) =>
      RowShareMark._(
        label: look.label(l10n),
        face: look.noteAvatar ? look.partner ?? const AppUser(uid: '') : null,
      );

  /// What a one-line row draws before its count, or null for the words
  /// alone. Never scaled with the text, as the event avatar's badge is not:
  /// the row keeps its 48 dp at every scale.
  Widget? trailing(BuildContext context) {
    final face = this.face;
    final Widget mark;
    if (sign) {
      mark = Icon(
        Icons.group_rounded,
        size: RowMetrics.shareMarkSize,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    } else if (face != null) {
      mark = UserAvatar(user: face, radius: RowMetrics.partnerAvatarRadius);
    } else {
      return null;
    }
    return ExcludeSemantics(child: mark);
  }

  /// The face at the start of a two-line row's second line, or null. Inline
  /// rather than at the row's end, which would cost the title its width at
  /// every scale; the preview after it is what gives way.
  InlineSpan? inlineFace() {
    final face = this.face;
    if (face == null) return null;
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          end: RowMetrics.partnerFaceInlineGap,
        ),
        child: ExcludeSemantics(
          child: UserAvatar(
            user: face,
            radius: RowMetrics.partnerFaceInlineRadius,
          ),
        ),
      ),
    );
  }

  /// [content] with [label] read first: inside the row's ink, so the merged
  /// row reads "From Maria, Recipes, 40".
  Widget labelled(Widget content) => Semantics(label: label, child: content);
}
