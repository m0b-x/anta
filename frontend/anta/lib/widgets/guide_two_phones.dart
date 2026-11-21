import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/guide_metrics.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/guide_share_world.dart';
import '../models/sync_guide_tries.dart';
import 'calendar_guide_stage_slot.dart';
import 'calendar_guide_try_card.dart';
import 'form_rows.dart';
import 'settings_section_list.dart';

/// What the flip says of the phone not in view (`docs/guide-hub-roadmap.md`
/// §11.8 D): nothing, a change on its way to it, or a change that reached
/// it since she last looked.
enum GuideFlipDot { none, ring, filled }

/// The two-phone stage's flip (D42): the settings kit's segmented control,
/// one segment a phone, the full width of the card. A dot after a label
/// says that phone changed; its slot is always there, so the label never
/// moves when a dot comes or goes.
///
/// Side by side while every word fits its half, measured by the kit's own
/// rule with the dot's room taken off; stacked otherwise, as the kit's
/// choice row stacks.
class GuideTwoPhonesFlip extends StatelessWidget {
  const GuideTwoPhonesFlip({
    super.key,
    required this.selected,
    required this.labels,
    required this.dots,
    required this.identifiers,
    required this.onSelected,
  });

  final GuidePhone selected;
  final Map<GuidePhone, String> labels;
  final Map<GuidePhone, GuideFlipDot> dots;
  final Map<GuidePhone, String> identifiers;
  final ValueChanged<GuidePhone> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = settingsChoiceWordsFit(
          context,
          labels.values,
          constraints.maxWidth / labels.length,
          trailingExtent: GuideMetrics.flipDotSize + GuideMetrics.flipDotGap,
        );
        return SizedBox(
          width: double.infinity,
          child: SegmentedButton<GuidePhone>(
            direction: horizontal ? Axis.horizontal : Axis.vertical,
            style: settingsSegmentedStyle(
              colorScheme,
              shape: horizontal
                  ? null
                  : const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(
                        Radius.circular(FormMetrics.menuRadius),
                      ),
                    ),
            ),
            showSelectedIcon: false,
            segments: [
              for (final phone in GuidePhone.values)
                ButtonSegment<GuidePhone>(
                  value: phone,
                  label: _label(
                    l10n,
                    colorScheme,
                    labels[phone]!,
                    dots[phone] ?? GuideFlipDot.none,
                    identifiers[phone],
                  ),
                ),
            ],
            selected: {selected},
            onSelectionChanged: (selection) => onSelected(selection.first),
          ),
        );
      },
    );
  }

  /// The label, its gap and the dot's slot. The dot is said in words on the
  /// label's node — the segment is one node, and a mark alone says nothing
  /// to a screen reader; the coach line's live region announces the rest.
  Widget _label(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    String label,
    GuideFlipDot dot,
    String? identifier,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Semantics(
            identifier: identifier,
            child: Text(
              label,
              textAlign: TextAlign.center,
              // As wide as its longest line, not the line box: a label that
              // wraps ("Telefonul lui Sam") keeps its dot beside the word
              // instead of at the segment's edge.
              textWidthBasis: TextWidthBasis.longestLine,
              semanticsLabel: switch (dot) {
                GuideFlipDot.none => null,
                GuideFlipDot.ring => l10n.syncGuidePhoneSyncing(label),
                GuideFlipDot.filled => l10n.syncGuidePhoneChanged(label),
              },
            ),
          ),
        ),
        const SizedBox(width: GuideMetrics.flipDotGap),
        SizedBox.square(
          dimension: GuideMetrics.flipDotSize,
          child: dot == GuideFlipDot.none
              ? null
              : DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dot == GuideFlipDot.filled
                        ? colorScheme.primary
                        : null,
                    border: dot == GuideFlipDot.ring
                        ? Border.all(
                            color: colorScheme.primary,
                            width: FormMetrics.shareOutlineWidth,
                          )
                        : null,
                  ),
                ),
        ),
      ],
    );
  }
}

/// One phone as a card draws it: its bar's mark and the area it shows, its
/// list — null when it has nothing to show, then [empty] stands centred in
/// its place — the list at its tallest for the card's steps, and the
/// control pinned under the list, if the phone has one.
@immutable
class GuidePhoneView {
  const GuidePhoneView({
    required this.mark,
    required this.area,
    required this.list,
    required this.template,
    this.empty,
    this.control,
    this.backSlot = false,
    this.onBack,
    this.backIdentifier,
    this.trailing,
  }) : assert(list != null || empty != null),
       assert(onBack == null || backSlot);

  final Widget mark;

  /// The page the phone has open, as the app titles it ("Calendar",
  /// "Notes"); the frame puts whose phone it is before it (§11.8 G).
  final String area;
  final Widget? list;

  /// The list in its tallest state over the card's steps — the seed and
  /// every row a step adds — laid out unseen to size the phone (D55).
  final Widget template;

  final String? empty;
  final Widget? control;

  /// The phone can open something of its own — Sam's folder — and its bar
  /// keeps a 48 dp back button's room in every state, so opening it and
  /// coming back never changes the phone's height (D55).
  final bool backSlot;

  /// Back out of what the phone has open; null while it has nothing open,
  /// and the slot stands empty.
  final VoidCallback? onBack;
  final String? backIdentifier;

  /// A control of the phone's own at the bar's end — the offline card's
  /// airplane toggle — in a 48 dp box flush with the bar's end, standing in
  /// every state so the bar never changes height.
  final Widget? trailing;
}

/// The phone's bar (§11.8 G): a mark that says whose phone this is — never a
/// second colour — and a title in the caption's ink, "{whose phone} ·
/// {area}", so the words say it too. Clamped with the flip, and one node
/// read by its title.
class GuidePhoneBar extends StatelessWidget {
  const GuidePhoneBar({
    super.key,
    required this.mark,
    required this.title,
    this.backSlot = false,
    this.tall = false,
    this.onBack,
    this.backIdentifier,
    this.trailing,
  });

  final Widget mark;
  final String title;

  /// [GuidePhoneView.backSlot]: the bar is a back button tall in every
  /// state, the button drawn before the mark while [onBack] is set.
  final bool backSlot;

  /// The bar is a back button tall though it has no slot of its own: the
  /// other phone's bar has one, and both stand at one height.
  final bool tall;
  final VoidCallback? onBack;
  final String? backIdentifier;

  /// [GuidePhoneView.trailing].
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final back = onBack;
    final end = trailing;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: GuideMetrics.phoneBarMaxTextScale,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: tall || backSlot || end != null
              ? FormMetrics.trailingButtonSize
              : GuideMetrics.phoneBarMinHeight,
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: back == null ? RowMetrics.groupInset : 0,
            end: end == null ? RowMetrics.groupInset : 0,
          ),
          child: Row(
            children: [
              Expanded(child: _titled(context, colorScheme, back)),
              if (end != null)
                SizedBox.square(
                  dimension: FormMetrics.trailingButtonSize,
                  child: end,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The back button, the mark and the title: one node, read by its title.
  /// The trailing control stays a node of its own beside it.
  Widget _titled(
    BuildContext context,
    ColorScheme colorScheme,
    VoidCallback? back,
  ) {
    return Semantics(
      container: true,
      child: Row(
        children: [
          if (back != null)
            Semantics(
              identifier: backIdentifier,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: AppLocalizations.of(context)!.back,
                color: colorScheme.onSurfaceVariant,
                onPressed: back,
              ),
            ),
          ExcludeSemantics(
            child: SizedBox.square(
              dimension: GuideMetrics.phoneMarkSize,
              child: Center(child: mark),
            ),
          ),
          const SizedBox(width: GuideMetrics.phoneMarkGap),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: RowMetrics.secondLineFontSize,
                fontWeight: FontWeight.w500,
                height:
                    FormMetrics.captionLineHeight /
                    RowMetrics.secondLineFontSize,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A two-phone stage (§11.3): the phone in view, one at a time, at the
/// height of the taller phone's tallest state (D55) — every phone's
/// template is laid out unseen in one stack, as the categories card sizes
/// its list — so a flip, a row arriving or a row leaving moves nothing under
/// the finger. Only the list scrolls, inside a [GuideStageSlot], for rows
/// past its template; the control stays pinned under it.
class GuideTwoPhones extends StatelessWidget {
  const GuideTwoPhones({
    super.key,
    required this.shown,
    required this.phones,
    required this.labels,
  });

  final GuidePhone shown;
  final Map<GuidePhone, GuidePhoneView> phones;

  /// The flip's word for each phone, which leads its bar's title.
  final Map<GuidePhone, String> labels;

  /// "Sam's phone · Calendar": one string, so each language orders it.
  String _title(AppLocalizations l10n, GuidePhone phone) =>
      l10n.syncGuidePhoneBar(labels[phone]!, phones[phone]!.area);

  /// Every bar of the card is a button tall once one phone's is — Sam's
  /// back slot, her trailing control — so a flip never moves the list under
  /// it. The bar's words are one line at its 1.3 clamp, so the slots are
  /// what can differ.
  bool get _tallBars =>
      phones.values.any((phone) => phone.backSlot || phone.trailing != null);

  List<Widget> _under(GuidePhoneView view) => [
    if (view.control case final control?) ...[
      const SizedBox(height: RowMetrics.groupGap),
      control,
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final view = phones[shown]!;
    final list = view.list;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        ExcludeSemantics(
          child: ExcludeFocus(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0,
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    for (final MapEntry(key: name, value: phone)
                        in phones.entries)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          GuidePhoneBar(
                            mark: phone.mark,
                            title: _title(l10n, name),
                            backSlot: phone.backSlot,
                            tall: _tallBars,
                            // The slot's room only: the control is drawn
                            // once, on the phone in view.
                            trailing: phone.trailing == null
                                ? null
                                : const SizedBox.shrink(),
                          ),
                          phone.template,
                          ..._under(phone),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GuidePhoneBar(
                mark: view.mark,
                title: _title(l10n, shown),
                backSlot: view.backSlot,
                tall: _tallBars,
                onBack: view.onBack,
                backIdentifier: view.backIdentifier,
                trailing: view.trailing,
              ),
              Expanded(
                child: list == null
                    ? _GuidePhoneEmpty(view.empty!)
                    : GuideStageSlot(child: SingleChildScrollView(child: list)),
              ),
              ..._under(view),
            ],
          ),
        ),
      ],
    );
  }
}

/// A phone with nothing to show says so in one line, centred where its list
/// would stand (§11.8 L), at the full text scale and with no glyph.
class _GuidePhoneEmpty extends StatelessWidget {
  const _GuidePhoneEmpty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: RowMetrics.groupInset),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: FormMetrics.labelSize,
            height: FormMetrics.labelLineHeight / FormMetrics.labelSize,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// The base of every two-phone card: the card's [world], which phone is in
/// view, the flip's dots and the beat that carries a change to the other
/// phone (D47). A step is done when the world shows it ([GuideShareStep]),
/// checked after every change; opening the other phone is the one step
/// that is the flip itself ([GuideFlipStep], D44).
///
/// A card supplies its world ([seedWorld]), its phones ([buildPhone]) and
/// the flip's words ([phoneLabel]), which lead each phone's bar; its
/// controls change the world, then [send] what travels and [settle]; a
/// sheet, menu or dialog it raises goes through [openOnce].
abstract class GuideTwoPhonesDemo extends GuideCardDemo {
  GuideTwoPhonesDemo(super.card, {required this.book}) : slug = card.slug;

  /// The book's and the card's slugs, for the stage's ids (D51).
  final String book;
  final String slug;

  GuideShareWorld? _world;

  /// The card's one world, made in the page's language the first time the
  /// stage is drawn — as the categories card seeds its rows — so a later
  /// change of language keeps what she did on it.
  GuideShareWorld get world => _world!;

  @protected
  GuideShareWorld seedWorld(AppLocalizations l10n);

  void _ensureWorld(BuildContext context) =>
      _world ??= seedWorld(AppLocalizations.of(context)!);

  GuidePhone _phone = GuidePhone.here;

  /// The phone in view.
  GuidePhone get phone => _phone;

  /// The beat under way, and every phone a change was sent to during it.
  Timer? _beat;
  final Set<GuidePhone> _bound = {};

  /// The phones a landing delivered something to since she last looked.
  final Set<GuidePhone> _unseen = {};

  /// What the flip says of [phone] (§11.8 D): a ring while something is
  /// really on its way to it — a share taken back within the beat leaves
  /// nothing travelling — filled once a landing delivered something there,
  /// and nothing on the phone in view.
  GuideFlipDot dotOf(GuidePhone phone) {
    // The flip is drawn above the stage, before the stage seeds the world:
    // nothing has moved yet.
    if (phone == _phone || _world == null) return GuideFlipDot.none;
    if ((_bound.contains(phone) || waitsFor(phone)) && inFlightTo(phone)) {
      return GuideFlipDot.ring;
    }
    if (_unseen.contains(phone)) return GuideFlipDot.filled;
    return GuideFlipDot.none;
  }

  /// Whether a change she made has yet to reach [phone]. The world carries
  /// changes one way today — hers, to the other phone — so its one flag
  /// answers; a card whose changes travel both ways answers per phone.
  @protected
  bool inFlightTo(GuidePhone phone) => world.inFlight;

  /// A change for [phone] is held with no beat under way — a phone in
  /// airplane mode sends nothing (spec §4) — and its dot rings for as long
  /// as it waits, until a [send] carries it. Nothing waits on a card
  /// whose changes always set out at once.
  @protected
  bool waitsFor(GuidePhone phone) => false;

  /// A change is on its way to the other phone.
  bool get beating => _beat != null;

  /// The phone's bar sits on the stage's top hairline (§11.8 A).
  @override
  bool get stageTopFlush => true;

  /// The card shows her phone alone: no flip, the stage as tall as her
  /// phone's tallest state, every other rule the same — for a card about
  /// one phone (`docs/guide-hub-roadmap.md` §11.4).
  @protected
  bool get onePhone => false;

  List<GuidePhone> get _phones =>
      onePhone ? const [GuidePhone.here] : GuidePhone.values;

  /// The flip's word for [phone].
  @protected
  String phoneLabel(AppLocalizations l10n, GuidePhone phone);

  /// [phone] as it stands in [world] now.
  @protected
  GuidePhoneView buildPhone(BuildContext context, GuidePhone phone);

  @override
  Widget? buildAboveStage(BuildContext context) {
    if (onePhone) return null;
    final l10n = AppLocalizations.of(context)!;
    return GuideTwoPhonesFlip(
      selected: _phone,
      labels: {
        for (final phone in GuidePhone.values) phone: phoneLabel(l10n, phone),
      },
      dots: {for (final phone in GuidePhone.values) phone: dotOf(phone)},
      identifiers: {
        for (final phone in GuidePhone.values)
          phone: SemanticsIds.guideBookTryPhone(book, slug, phone.name),
      },
      onSelected: select,
    );
  }

  @override
  Widget buildStage(BuildContext context) {
    _ensureWorld(context);
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      container: true,
      identifier: SemanticsIds.guideBookTryStage(book, slug),
      child: GuideTwoPhones(
        shown: _phone,
        phones: {
          for (final phone in _phones) phone: buildPhone(context, phone),
        },
        labels: {for (final phone in _phones) phone: phoneLabel(l10n, phone)},
      ),
    );
  }

  /// Shows [phone]. Looking at it is what clears its dot — never a timer.
  void select(GuidePhone phone) {
    if (phone == _phone) return;
    _phone = phone;
    _unseen.remove(phone);
    settle();
  }

  /// What she just changed sets out for [to], and after
  /// [GuideMetrics.syncBeat] it lands ([land]). A second change during the
  /// beat starts it again and everything sent lands together.
  @protected
  void send(GuidePhone to) {
    _bound.add(to);
    _beat?.cancel();
    _beat = Timer(GuideMetrics.syncBeat, _arrive);
  }

  void _arrive() {
    _beat = null;
    final carried = {
      for (final phone in _bound)
        if (inFlightTo(phone)) phone,
    };
    _bound.clear();
    land();
    // A phone she looks at shows the change landing in front of her, so it
    // earns no dot.
    _unseen.addAll(carried.where((phone) => phone != _phone));
    settle(byHer: false);
  }

  /// The beat's end: what was in flight reaches the other phone.
  @protected
  void land() => world.deliver();

  /// Marks every step the world now shows, then redraws. A change she made
  /// takes down a standing report ([changed]); the beat's landing is no
  /// act of hers, and a step it marks leaves the report standing.
  @protected
  void settle({bool byHer = true}) {
    var marked = false;
    for (final step in steps) {
      if (hasDone(step.action)) continue;
      final shows = switch (step) {
        GuideShareStep(:final done) => done(world),
        GuideFlipStep(:final to, :final ready) => _phone == to && ready(world),
        _ => false,
      };
      if (!shows) continue;
      did(step.action, keepReport: !byHer);
      marked = true;
    }
    if (marked) return;
    if (byHer) {
      changed();
    } else {
      redraw();
    }
  }

  bool _sheetOpen = false;

  /// Runs [open] — a sheet, a menu or a dialog the stage raises, and what
  /// follows its answer — unless one is already up: a double tap would
  /// otherwise stack a second over the first.
  @protected
  Future<void> openOnce(Future<void> Function() open) async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    try {
      await open();
    } finally {
      _sheetOpen = false;
    }
  }

  @override
  void dispose() {
    _beat?.cancel();
    _beat = null;
    super.dispose();
  }
}
