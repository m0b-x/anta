import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/share_copy.dart';
import 'form_rows.dart';

/// A fixed reading of [EventShareRow]'s second line, one its caption slot
/// can be sized for.
enum EventShareReading {
  /// Not shared.
  off,

  /// Shared with the partner, by the event's own mark.
  on,

  /// This database does not sync yet, so nothing can be shared.
  needsSync,
}

/// The event editor's share switch (share surfaces §6.6), drawn by the
/// editor and by the sync guide's stages (`docs/guide-hub-roadmap.md`
/// §11.4) from one place, so the two never drift: the partner's name in its
/// label, two lines in every state, the second in a slot as tall as the
/// tallest of [reserve], and a category's reading cut to that slot — a
/// category pick that shares the event, or a flip, moves nothing below it.
///
/// Pure: it reads nothing and writes nothing; the caller holds the mark
/// and the facts.
class EventShareRow extends FormDividedRow {
  const EventShareRow({
    super.key,
    required this.partnerName,
    required this.ready,
    required this.value,
    required this.onChanged,
    this.sharedThrough,
    this.reserve = EventShareReading.values,
    this.identifier,
    this.onOpenSync,
  });

  /// The partner as the label and the "on" reading name them.
  final String partnerName;

  /// Sharing can happen now (`ShareReady`); otherwise the row says sync is
  /// needed, stands off and disabled, and offers [onOpenSync].
  final bool ready;

  /// The event's own mark.
  final bool value;

  /// Null disables the switch, as a category's share or a lost pair does.
  final ValueChanged<bool>? onChanged;

  /// The name of the category that shares the event, if one does: the row
  /// reads on and disabled, and its line says why.
  final String? sharedThrough;

  /// The fixed readings the caption slot is sized for: the editor's every
  /// reading, a stage only those it shows, so it spends no line on one it
  /// never draws.
  final List<EventShareReading> reserve;

  final String? identifier;

  /// Where the one step missing is taken, while not [ready].
  final VoidCallback? onOpenSync;

  @override
  double get dividerIndent => FormMetrics.dividerIndentGlyph;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onLine = ShareCopy.sentence(l10n.shareEventOn(partnerName));
    String reading(EventShareReading reading) => switch (reading) {
      EventShareReading.off => l10n.shareEventOff,
      EventShareReading.on => onLine,
      EventShareReading.needsSync => l10n.shareNeedsSync,
    };
    final through = ready ? sharedThrough : null;
    final String subtitle;
    if (!ready) {
      subtitle = l10n.shareNeedsSync;
    } else if (through != null) {
      subtitle = l10n.shareThroughCategory(through);
    } else {
      subtitle = value ? onLine : l10n.shareEventOff;
    }
    return FormSwitchRow(
      glyph: Icons.group_rounded,
      identifier: identifier,
      label: l10n.shareWithPartner(partnerName),
      subtitle: subtitle,
      // The fixed readings size the slot; "On for everything in {category}"
      // is cut to it, so one long shared category name never gives every
      // event's row a blank second line.
      subtitleTemplates: [for (final fixed in reserve) reading(fixed)],
      subtitleFitsTemplates: true,
      value: ready && (through != null || value),
      onChanged: ready && through == null ? onChanged : null,
      onDisabledTap: ready ? null : onOpenSync,
      onDisabledTapHint: l10n.shareOpensSyncHint,
    );
  }
}
