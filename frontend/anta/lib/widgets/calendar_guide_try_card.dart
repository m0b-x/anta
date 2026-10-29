import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import '../constants/guide_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_guide_content.dart';
import 'calendar_guide_rows.dart';
import 'form_rows.dart';
import 'settings_section_list.dart';

/// What one "Try it" card shows and remembers: its stage, built from the real
/// widgets of the page's task, and the caption that says what the last
/// action did.
///
/// Owned by the page's `State`, never by the card: the kit's list disposes a
/// card scrolled out of view, and a demo that lived in it would forget what
/// she did the moment she scrolled down to read about it. Nothing here is
/// saved — every sheet a stage opens runs in its sandbox mode and its answer
/// lands in the demo.
abstract class GuideCardDemo extends ChangeNotifier {
  /// The owner's calendar look, for the pickers and the add button a stage
  /// draws. The defaults until the page has read it, and only read for a
  /// demo that asks ([needsAppearance]).
  CalendarAppearance get appearance => _appearance;
  CalendarAppearance _appearance = const CalendarAppearance();
  set appearance(CalendarAppearance value) {
    _appearance = value;
    notifyListeners();
  }

  bool get needsAppearance => false;

  /// The last action's caption, written in whatever language the page is
  /// in when it is drawn; null while nothing has happened.
  String Function(AppLocalizations l10n)? _said;

  /// The caption now. Null is the reserved, empty slot of a card with no
  /// resting caption (D30).
  String? caption(AppLocalizations l10n) => _said?.call(l10n) ?? idle(l10n);

  /// The caption before the first action.
  String? idle(AppLocalizations l10n);

  /// Every caption the card can show, each at its longest. The slot is as
  /// tall as the tallest, so a caption changes words and never the card's
  /// height. Called once per locale.
  List<String> candidates(AppLocalizations l10n);

  Widget buildStage(BuildContext context);

  /// Records what just happened and redraws the card.
  @protected
  void say(String Function(AppLocalizations l10n) caption) {
    _said = caption;
    notifyListeners();
  }

  /// Redraws the card after a change the caption does not name.
  @protected
  void changed() => notifyListeners();
}

/// A title as a caption quotes it: cut at
/// [GuideMetrics.captionTitleMaxChars] so a caption slot can be sized for
/// any title she types.
String calendarGuideQuote(String title) {
  final characters = title.characters;
  if (characters.length <= GuideMetrics.captionTitleMaxChars) return title;
  return '${characters.take(GuideMetrics.captionTitleMaxChars)}…';
}

/// The stand-in for any typed title among a slot's candidates: as wide as a
/// title can be once [calendarGuideQuote] has cut it.
final String calendarGuideLongestQuote =
    '${'W' * GuideMetrics.captionTitleMaxChars}…';

/// The long weekday date the guide's captions write, at its widest in
/// [dates]' language over a whole year, for a caption slot's candidates.
String calendarGuideLongestDate(DateFormat dates) {
  var longest = '';
  for (var day = 0; day < 365; day++) {
    final text = dates.format(DateTime.utc(2027, 1, 1 + day));
    if (text.length > longest.length) longest = text;
  }
  return longest;
}

/// The page's "Try it" card: the lead-in as its one entry — so the kit's
/// search finds it — over the card's body.
SettingsSectionData calendarGuideTrySection({
  required AppLocalizations l10n,
  required CalendarGuideTopic topic,
  required String lead,
  required GuideCardDemo demo,
  required List<String> candidates,
}) {
  return SettingsSectionData(
    icon: calendarGuidePracticeIcon,
    title: l10n.calendarGuideTryIt,
    entries: [
      SettingsEntry(
        title: lead,
        titleStyle: calendarGuideParagraphStyle,
        identifier: SemanticsIds.calendarGuideTry(topic.slug),
        builder: (context, title, _) => CalendarGuideTryCard(
          slug: topic.slug,
          lead: title,
          demo: demo,
          candidates: candidates,
        ),
      ),
    ],
  );
}

/// The body of a "Try it" card: the lead-in, the stage, the live caption.
///
/// No ink, no chevron, no tap of its own — the card is a place to try
/// things, and only the stage's real controls answer a finger. Stateless
/// over [demo], which outlives it.
class CalendarGuideTryCard extends StatelessWidget {
  const CalendarGuideTryCard({
    super.key,
    required this.slug,
    required this.lead,
    required this.demo,
    required this.candidates,
  });

  final String slug;
  final Widget lead;
  final GuideCardDemo demo;
  final List<String> candidates;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: demo,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context)!;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            GuideMetrics.cardInset,
            0,
            GuideMetrics.cardInset,
            GuideMetrics.cardInset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              lead,
              const SizedBox(height: GuideMetrics.leadToStage),
              RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.pageGround,
                    border: Border.all(
                      color: colorScheme.outlineVariant,
                      width: GuideMetrics.stageOutline,
                    ),
                    borderRadius: BorderRadius.circular(
                      GuideMetrics.stageRadius,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(GuideMetrics.stagePadding),
                    child: demo.buildStage(context),
                  ),
                ),
              ),
              const SizedBox(height: GuideMetrics.stageToCaption),
              FormCaptionSlot(
                candidates: [
                  for (final text in candidates) FormCaption(text: text),
                ],
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  identifier: SemanticsIds.calendarGuideTryCaption(slug),
                  child: FormCaption(text: demo.caption(l10n) ?? ''),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
