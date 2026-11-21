import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/guide_metrics.dart';
import '../constants/semantics_ids.dart';
import '../controllers/guide_setup_reader.dart';
import '../l10n/app_localizations.dart';
import '../services/app_navigator.dart';
import 'form_rows.dart';
import 'settings_section_list.dart';

/// Opens the real screen a setup row leads to: Sync & sharing, or with
/// [sharing] the Sharing page over it.
typedef GuideSetupOpen =
    void Function(BuildContext context, {required bool sharing});

/// Back to the Sync & sharing page the guide was opened over, when it was,
/// rather than a second one over the guide.
void _openSyncSettings(BuildContext context, {required bool sharing}) =>
    unawaited(
      AppNavigator.toSyncSettings(context, openSharing: sharing, goBack: true),
    );

/// The card's rows, in the order the steps are taken; each one's name is
/// its id's suffix (`SemanticsIds.guideSyncSetupRow`).
enum GuideSetupStep { account, sync, pair, share }

/// The sync book hub's "Your setup" (`docs/guide-hub-roadmap.md` D48, §11.8
/// I): one row per [GuideSetupStep], each the state in words beside a
/// done or not-yet glyph, opening the screen where the step is taken —
/// never dimmed, since a row not yet done still opens it. On a build without
/// sync it is the one line the Sync section shows there.
///
/// [facts] is read by each row as it changes; whether sync exists is read
/// once, here, since the bound identity never changes while the app runs.
/// [opening] is told as a row opens its screen, before it does.
SettingsSectionData guideSetupSection(
  AppLocalizations l10n,
  ValueListenable<GuideSetupFacts> facts, {
  GuideSetupOpen open = _openSyncSettings,
  VoidCallback? opening,
}) {
  void opened(BuildContext context, {required bool sharing}) {
    opening?.call();
    open(context, sharing: sharing);
  }

  return SettingsSectionData(
    icon: Icons.checklist_rounded,
    title: l10n.syncGuideSetupTitle,
    identifier: SemanticsIds.guideSyncSetup,
    entries: facts.value.unavailable
        ? [
            SettingsEntry(
              title: l10n.syncThisDatabaseUnavailable,
              identifier: SemanticsIds.guideSyncSetupRow('unavailable'),
              builder: (context, title, description) => ListTile(
                contentPadding: GuideMetrics.hubRowPadding,
                title: Text(
                  l10n.syncThisDatabaseUnavailable,
                  style: settingsCaptionStyle.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ]
        : [
            for (final step in GuideSetupStep.values)
              SettingsEntry(
                // Never searched (D54): the hub shows this section only
                // while no query is typed.
                title: '',
                identifier: SemanticsIds.guideSyncSetupRow(step.name),
                builder: (context, title, description) =>
                    _SetupRow(step: step, facts: facts, open: opened),
              ),
          ],
  );
}

/// One state a row words: the state, and — when an earlier step comes
/// first — the caption that names it. A [named] title carries a name, which
/// may be any length: it is cut at two lines.
typedef _Words = ({String title, String? caption, bool named});

_Words _fixed(String title, [String? caption]) =>
    (title: title, caption: caption, named: false);

_Words _named(String title) => (title: title, caption: null, named: true);

/// A named title at its tallest, as [FormMetrics.valueMaxLines] cuts it,
/// whatever the name: that many empty lines.
final String _namedTitleAtMost = List.filled(
  FormMetrics.valueMaxLines,
  '',
).join('\n');

/// What a row shows for the facts as they stand, and every state it may
/// show, which size it: [words] is null while its fact is not known.
class _Face {
  const _Face(this.done, this.words, this.templates);

  final bool? done;
  final _Words? words;

  /// Every state the row may word, a name left empty and a count at each
  /// plural form: the language's words alone, so neither the slot nor the
  /// chevron they decide changes when a fact lands.
  final List<_Words> templates;
}

_Face _faceOf(
  GuideSetupStep step,
  GuideSetupFacts facts,
  AppLocalizations l10n,
) {
  // The earliest step before this one that is known not to be done; a step
  // not known yet claims nothing.
  String? first({bool afterSync = false, bool afterPair = false}) {
    if (facts.signedIn == false) return l10n.syncGuideSetupAccountFirst;
    if (afterSync) {
      switch (facts.sync) {
        case GuideSetupSync.off:
          return l10n.syncGuideSetupSyncFirst;
        // Not off, so no switch to turn: the obstacle is the pause.
        case GuideSetupSync.otherAccount:
          return l10n.syncGuideSetupSyncPausedFirst;
        case GuideSetupSync.on || null:
          break;
      }
    }
    if (afterPair && facts.paired == false) {
      return l10n.syncGuideSetupPairFirst;
    }
    return null;
  }

  final accountFirst = l10n.syncGuideSetupAccountFirst;
  switch (step) {
    case GuideSetupStep.account:
      final name = facts.accountName;
      return _Face(
        facts.signedIn,
        switch (facts.signedIn) {
          null => null,
          true when name != null => _named(
            l10n.syncGuideSetupAccountDone(name),
          ),
          true => _fixed(l10n.syncGuideSetupAccountDoneUnnamed),
          false => _fixed(l10n.syncGuideSetupAccountTodo),
        },
        [
          _named(l10n.syncGuideSetupAccountDone('')),
          _fixed(l10n.syncGuideSetupAccountDoneUnnamed),
          _fixed(l10n.syncGuideSetupAccountTodo),
        ],
      );
    case GuideSetupStep.sync:
      final todo = l10n.syncGuideSetupSyncTodo(l10n.syncThisDatabase);
      return _Face(
        switch (facts.sync) {
          null => null,
          final sync => sync == GuideSetupSync.on,
        },
        switch (facts.sync) {
          null => null,
          GuideSetupSync.on => _fixed(l10n.syncGuideSetupSyncDone),
          GuideSetupSync.off => _fixed(todo, first()),
          // Sync & sharing draws no "Sync this database" here: the row says
          // what its status line says.
          GuideSetupSync.otherAccount => _fixed(l10n.syncPausedOtherAccount),
        },
        [
          _fixed(l10n.syncGuideSetupSyncDone),
          _fixed(todo),
          _fixed(todo, accountFirst),
          _fixed(l10n.syncPausedOtherAccount),
        ],
      );
    case GuideSetupStep.pair:
      final name = facts.partnerName;
      final todo = l10n.syncGuideSetupPairTodo;
      return _Face(
        facts.paired,
        switch (facts.paired) {
          null => null,
          true when name != null => _named(l10n.syncGuideSetupPairDone(name)),
          true => _fixed(l10n.pairingPartnerUnknown),
          false => _fixed(todo, first()),
        },
        [
          _named(l10n.syncGuideSetupPairDone('')),
          _fixed(l10n.pairingPartnerUnknown),
          _fixed(todo),
          _fixed(todo, accountFirst),
        ],
      );
    case GuideSetupStep.share:
      final shared = facts.shared;
      final todo = l10n.syncGuideSetupShareTodo;
      return _Face(
        shared == null ? null : shared > 0,
        switch (shared) {
          null => null,
          > 0 => _fixed(l10n.syncGuideSetupShareDone(shared)),
          _ => _fixed(todo, first(afterSync: true, afterPair: true)),
        },
        [
          // One, few and other in every language.
          for (final count in const [1, 2, 20])
            _fixed(l10n.syncGuideSetupShareDone(count)),
          _fixed(todo),
          for (final caption in [
            accountFirst,
            l10n.syncGuideSetupSyncFirst,
            l10n.syncGuideSetupSyncPausedFirst,
            l10n.syncGuideSetupPairFirst,
          ])
            _fixed(todo, caption),
        ],
      );
  }
}

/// The spaces the line breaker breaks at, as the hub's glyph rule has them.
final RegExp _breakingSpaces = RegExp(
  '[ \\t\\n\\u1680\\u2000-\\u2006\\u2008-\\u200A\\u205F\\u3000]+',
);

/// Whether every word of every state the card may word fits the title
/// column a row [width] wide leaves beside the glyph and the chevron (§11.8
/// I): when one does not, every row drops its chevron together, before any
/// word breaks mid-way — the state glyph never drops, it is the state. A
/// name is not one of those words: it arrives with its fact, and the card
/// keeps its shape when it does.
bool _chevronFits(BuildContext context, AppLocalizations l10n, double width) {
  final theme = Theme.of(context);
  final style = theme.textTheme.bodyLarge?.merge(
    const TextStyle(
      fontSize: GuideMetrics.hubTitleFontSize,
      fontWeight: GuideMetrics.hubTitleFontWeight,
    ),
  );
  final column =
      GuideMetrics.hubGlyphSize +
      GuideMetrics.hubTitleGap +
      theme.visualDensity.horizontal * 2;
  final room = width - GuideMetrics.hubRowPadding.horizontal - column * 2;
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  );
  try {
    for (final step in GuideSetupStep.values) {
      for (final words in _faceOf(
        step,
        const GuideSetupFacts(),
        l10n,
      ).templates) {
        for (final word in words.title.split(_breakingSpaces)) {
          painter
            ..text = TextSpan(text: word, style: style)
            ..layout();
          // An exact fit can still wrap in the engine.
          if (room - painter.width < 0.5) return false;
        }
      }
    }
    return true;
  } finally {
    painter.dispose();
  }
}

/// A setup row in the hub row's geometry: the state glyph, the state in
/// words over its caption, a chevron. Its words sit in a slot as tall as
/// the tallest state it may word, so nothing moves when a fact arrives;
/// until its fact is known it keeps that slot and claims nothing — no
/// glyph, no words, no tap.
class _SetupRow extends StatelessWidget {
  const _SetupRow({
    required this.step,
    required this.facts,
    required this.open,
  });

  final GuideSetupStep step;
  final ValueListenable<GuideSetupFacts> facts;
  final GuideSetupOpen open;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GuideSetupFacts>(
      valueListenable: facts,
      builder: (context, facts, _) => LayoutBuilder(
        builder: (context, constraints) =>
            _row(context, facts, constraints.maxWidth),
      ),
    );
  }

  Widget _row(BuildContext context, GuideSetupFacts facts, double width) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final face = _faceOf(step, facts, l10n);
    final words = face.words;
    // Paired, the Sharing page; otherwise Sync & sharing, where pairing
    // starts — the Sharing page asked for unpaired would only wait there.
    final sharing = step == GuideSetupStep.share && facts.paired == true;

    Widget lines(_Words words) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          words.title,
          maxLines: words.named ? FormMetrics.valueMaxLines : null,
          overflow: words.named ? TextOverflow.ellipsis : null,
        ),
        if (words.caption case final caption?)
          Text(
            caption,
            style: settingsCaptionStyle.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );

    final glyph = switch (face.done) {
      null => null,
      true => Icon(
        Icons.check_circle_rounded,
        size: GuideMetrics.hubGlyphSize,
        color: colorScheme.primary,
      ),
      false => Icon(
        Icons.radio_button_unchecked_rounded,
        size: GuideMetrics.hubGlyphSize,
        color: colorScheme.onSurfaceVariant,
      ),
    };

    return MergeSemantics(
      child: Semantics(
        // A tooltip-like word is not spoken beside a label on Android 9+.
        hint: words != null && defaultTargetPlatform == TargetPlatform.android
            ? (sharing
                  ? l10n.syncGuideSetupOpensSharing
                  : l10n.shareOpensSyncHint)
            : null,
        child: ListTile(
          contentPadding: GuideMetrics.hubRowPadding,
          minLeadingWidth: GuideMetrics.hubGlyphSize,
          horizontalTitleGap: GuideMetrics.hubTitleGap,
          leading: ExcludeSemantics(
            child: SizedBox.square(
              dimension: GuideMetrics.hubGlyphSize,
              child: glyph,
            ),
          ),
          title: FormCaptionSlot(
            alignment: AlignmentDirectional.centerStart,
            candidates: [
              for (final template in face.templates) lines(template),
              // A name's title at its longest, over each caption the row
              // may carry: the slot holds it from the first frame.
              for (final caption in {
                for (final template in face.templates) template.caption,
              })
                lines((
                  title: _namedTitleAtMost,
                  caption: caption,
                  named: true,
                )),
            ],
            child: words == null ? const SizedBox.shrink() : lines(words),
          ),
          trailing: _chevronFits(context, l10n, width)
              ? Icon(
                  Icons.chevron_right_rounded,
                  size: GuideMetrics.hubGlyphSize,
                  color: colorScheme.onSurfaceVariant,
                )
              : null,
          onTap: words == null ? null : () => open(context, sharing: sharing),
        ),
      ),
    );
  }
}
