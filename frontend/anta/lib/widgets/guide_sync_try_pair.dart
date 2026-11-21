import 'package:flutter/material.dart';

import '../constants/guide_metrics.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_guide_content.dart' show calendarGuidePracticeIcon;
import '../models/guide_book.dart';
import '../models/guide_share_world.dart';
import '../models/share_overview.dart';
import '../models/sync_guide_tries.dart';
import '../pages/sharing_page.dart' show shareSummary, shareSummaryTemplates;
import '../services/pairing_service.dart';
import '../utils/pairing_error.dart';
import '../utils/settings_search.dart';
import 'calendar_guide_try_card.dart' show GuideCaptionAboveKeyboard;
import 'form_rows.dart';
import 'guide_share_rows.dart';
import 'guide_sync_phones.dart' show GuideTallest;
import 'guide_two_phones.dart';
import 'pairing_sheet_parts.dart';
import 'settings_section_list.dart';
import 'sync_settings_sections.dart';
import 'user_avatar.dart';

/// The `pair` card of the sync book (`docs/guide-hub-roadmap.md` §11.4):
/// both phones open on Sync & sharing's Pairing row, never paired. Her
/// phone holds the pairing sheet's invite half under it — Create a code,
/// then the code view (D43) — on the stage itself, not in a sheet, so the
/// coach line stays in view; Sam's holds the sheet's redeem half, and the
/// card's own "Fill in the code" (spec §5 K) stands above the stage. The right
/// code pairs both phones one beat later, and each row reads it as the page
/// does.
///
/// The code's life is held still: the stage shows the countdown as the
/// sheet first shows it — the service's real ten minutes — and never ticks
/// the clock, since nothing on a stage runs out while she reads.
class GuideSyncPairDemo extends GuideTwoPhonesDemo {
  GuideSyncPairDemo(super.card, {DateTime Function() now = DateTime.now})
    : _now = now,
      super(book: GuideBook.sync.slug);

  final DateTime Function() _now;

  /// The code her phone makes: eight characters of the service's own
  /// alphabet, as one it makes would be.
  static const String demoCode = 'K7M2Q9XP';

  /// Sam's field, its focus and the entry under it — what the caption is
  /// kept above once the keyboard rises (D22).
  final TextEditingController _field = TextEditingController();
  final FocusNode _focus = FocusNode();
  final GlobalKey _entryKey = GlobalKey();

  /// The unseen template's own field, holding a whole code: a field is
  /// never drawn twice over one controller.
  final TextEditingController _templateField = TextEditingController(
    text: PairingService.formatCode(demoCode),
  );

  /// Sam's last Connect was a code that is not hers: said under the field,
  /// as the sheet says a refused code, until the next Connect.
  bool _refused = false;

  String _control(String name) =>
      SemanticsIds.guideBookTryControl(book, slug, name);

  /// The world exists: the flip and "Fill in the code" above the stage are
  /// drawn before the stage first seeds it.
  bool _seeded = false;

  static String _copyReport(AppLocalizations l10n) =>
      l10n.syncGuideReportPairCopy(l10n.syncGuideDemoPartner);

  /// What the paired row on the phone of the one paired with [name] opens in
  /// the app: a stage navigates nowhere (D41), so it says so instead.
  static String _sharingReport(AppLocalizations l10n, String name) =>
      l10n.syncGuideReportPairSharing(l10n.sharingWithTitle(name));

  @override
  List<String> reports(AppLocalizations l10n) => [
    _copyReport(l10n),
    _sharingReport(l10n, l10n.syncGuideDemoPartner),
    _sharingReport(l10n, l10n.syncGuideDemoYou),
  ];

  /// The flip, and under it "Fill in the code": the guide's help, not the
  /// app's, so it stands on the card rather than inside Sam's phone, where
  /// it read as one of the sheet's controls. Always in its place, disabled but on
  /// Sam's phone while her code waits there, so nothing moves under the
  /// finger.
  @override
  Widget? buildAboveStage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final code = _seeded && phone == GuidePhone.there && !world.theirPaired
        ? world.code
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?super.buildAboveStage(context),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FormChip(
            label: l10n.syncGuidePairFill,
            glyph: calendarGuidePracticeIcon,
            selected: false,
            identifier: _control('fill'),
            onTap: code == null || world.redeeming ? null : () => _fill(code),
          ),
        ),
      ],
    );
  }

  /// Nobody is paired and no code is made.
  @override
  GuideShareWorld seedWorld(AppLocalizations l10n) {
    _seeded = true;
    final now = _now();
    return GuideShareWorld(
      day: DateTime.utc(now.year, now.month, now.day),
      events: const [],
      paired: false,
    );
  }

  @override
  String phoneLabel(AppLocalizations l10n, GuidePhone phone) => switch (phone) {
    GuidePhone.here => l10n.syncGuidePhoneYours,
    GuidePhone.there => l10n.syncGuidePhoneTheirs(l10n.syncGuideDemoPartner),
  };

  @override
  GuidePhoneView buildPhone(BuildContext context, GuidePhone phone) {
    final l10n = AppLocalizations.of(context)!;
    return switch (phone) {
      GuidePhone.here => GuidePhoneView(
        mark: GuideShareLooks.herMark(context),
        area: l10n.sharingSettings,
        list: _hers(context, l10n, live: true),
        template: _hers(context, l10n, live: false),
      ),
      GuidePhone.there => GuidePhoneView(
        mark: GuideShareLooks.samMark(l10n),
        area: l10n.sharingSettings,
        list: _sams(context, l10n, live: true),
        template: _sams(context, l10n, live: false),
      ),
    };
  }

  /// Her phone: the Pairing row as the page reads it — not paired, waiting
  /// over the code, or paired with Sam over what is shared — and under it
  /// Create a code, then the code view. Each part is as tall as its tallest
  /// state, so the phone never changes height (D55); [live] off, the parts
  /// are their tallest states alone — the frame's unseen template.
  Widget _hers(
    BuildContext context,
    AppLocalizations l10n, {
    required bool live,
  }) {
    final code = world.code;
    Widget row = const SizedBox.shrink();
    Widget body = const SizedBox.shrink();
    if (!live) {
      // Their tallest states alone, below.
    } else if (world.paired) {
      row = _paired(l10n, l10n.syncGuideDemoPartner, live: true, hers: true);
    } else if (code != null) {
      row = _invite(
        l10n,
        l10n.pairingWaiting,
        PairingService.formatCode(code),
        live: true,
      );
      body = _codeView(code, live: true);
    } else {
      row = _notPaired(l10n, live: true);
      body = PairingCreateCodeButton(
        busy: false,
        identifier: _control('create'),
        onPressed: _create,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GuideTallest(
          templates: [
            _notPaired(l10n, live: false),
            _invite(
              l10n,
              l10n.pairingWaiting,
              PairingService.formatCode(demoCode),
              live: false,
            ),
            _paired(l10n, l10n.syncGuideDemoPartner, live: false, hers: true),
          ],
          child: row,
        ),
        _sheetPart(
          GuideTallest(
            templates: [_codeView(demoCode, live: false)],
            child: body,
          ),
        ),
      ],
    );
  }

  /// Sam's phone: the same row, "Paired with you" once the pair lands, and
  /// under it the sheet's field and Connect — gone once paired, as the
  /// sheet closes itself.
  Widget _sams(
    BuildContext context,
    AppLocalizations l10n, {
    required bool live,
  }) {
    final paired = world.theirPaired;
    final invalid = PairingErrorMessages.of(
      l10n,
    ).resolve(PairingError.codeInvalid);
    final Widget body = paired || !live
        ? const SizedBox.shrink()
        : GuideCaptionAboveKeyboard(
            focusNode: _focus,
            caption: captionSlotKey,
            last: _entryKey,
            child: KeyedSubtree(
              key: _entryKey,
              child: PairingCodeEntry(
                controller: _field,
                focusNode: _focus,
                busy: world.redeeming,
                errorText: _refused ? invalid : null,
                errorMaxLines: GuideMetrics.pairErrorMaxLines,
                fieldIdentifier: _control('field'),
                connectIdentifier: _control('connect'),
                onSubmit: _connect,
              ),
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GuideTallest(
          templates: [
            _notPaired(l10n, live: false),
            _paired(l10n, l10n.syncGuideDemoYou, live: false, hers: false),
          ],
          child: !live
              ? const SizedBox.shrink()
              : paired
              ? _paired(l10n, l10n.syncGuideDemoYou, live: true, hers: false)
              : _notPaired(l10n, live: true),
        ),
        _sheetPart(
          GuideTallest(templates: [_entryTemplate(l10n, invalid)], child: body),
        ),
      ],
    );
  }

  /// The field at its tallest: a whole code in it and the refusal under it.
  Widget _entryTemplate(AppLocalizations l10n, String invalid) =>
      PairingCodeEntry(
        controller: _templateField,
        errorText: invalid,
        errorMaxLines: GuideMetrics.pairErrorMaxLines,
        fieldIdentifier: _control('field'),
        connectIdentifier: _control('connect'),
        onSubmit: (_) {},
      );

  /// The sheet's half under the row, inset as the page's rows are.
  Widget _sheetPart(Widget child) => Padding(
    padding: const EdgeInsets.fromLTRB(
      RowMetrics.groupInset,
      RowMetrics.groupGap,
      RowMetrics.groupInset,
      RowMetrics.groupInset,
    ),
    child: child,
  );

  /// "Fill in the code" (spec §5 K): types the code her phone shows into Sam's
  /// field, so nobody types eight characters to practise.
  void _fill(String code) {
    final text = PairingService.formatCode(code);
    _field.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// The sheet's code view, its countdown held at the life the code was
  /// made with; Copy says what it would do, since a stage copies nothing.
  Widget _codeView(String code, {required bool live}) {
    final madeAt = world.codeMadeAt ?? _now();
    return PairingCodeView(
      code: code,
      heldAt: madeAt,
      expiresAt:
          world.codeExpiresAt ?? madeAt.add(PairingService.inviteLifetime),
      codeIdentifier: _control('code'),
      selectable: false,
      copyIdentifier: live ? _control('copy') : null,
      onCopy: live ? () => say(_copyReport) : () {},
    );
  }

  /// The Pairing section as Sync & sharing draws it, its one row in [entry]
  /// — never the section's "How this works": a guide page does not link to
  /// itself.
  Widget _section(AppLocalizations l10n, SettingsEntry entry) =>
      SettingsSectionList(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        query: SettingsQuery.empty,
        sections: [
          SettingsSectionData(
            icon: Icons.link_rounded,
            title: l10n.pairingSection,
            entries: [entry],
          ),
        ],
      );

  Widget _notPaired(AppLocalizations l10n, {required bool live}) => _invite(
    l10n,
    l10n.pairingNotPaired,
    l10n.pairingNotPairedDesc,
    live: live,
  );

  /// The row while a pair can be made: no tap, since the sheet's half it
  /// would open already stands under it.
  Widget _invite(
    AppLocalizations l10n,
    String title,
    String description, {
    required bool live,
  }) => _section(
    l10n,
    SettingsEntry(
      title: title,
      description: description,
      identifier: live ? _control('row') : null,
      builder: (context, title, description) => PairingInviteTile(
        title: title,
        description: description,
        onTap: null,
      ),
    ),
  );

  /// The row once paired with [name]: the partner's face on her phone, the
  /// link glyph on Sam's, where her profile is not the guide's to draw; a
  /// new pair shares nothing yet. Not a door on a stage: a tap says where it
  /// leads in the app, so its chevron is not a dead end.
  Widget _paired(
    AppLocalizations l10n,
    String name, {
    required bool live,
    required bool hers,
  }) => _section(
    l10n,
    SettingsEntry(
      title: l10n.pairingPairedWith(name),
      description: shareSummary(l10n, ShareOverview.empty),
      identifier: live ? _control('row') : null,
      builder: (context, title, description) => PairedTile(
        title: title,
        description: description,
        summaryTemplates: shareSummaryTemplates(l10n),
        avatar: hers ? UserAvatar(user: GuideShareLooks.sam(l10n)) : null,
        onTap: live
            ? () => say(
                (l10n) => _sharingReport(
                  l10n,
                  hers ? l10n.syncGuideDemoPartner : l10n.syncGuideDemoYou,
                ),
              )
            : null,
      ),
    ),
  );

  /// Create a code: the code and its life, held on her phone. Nothing
  /// travels until Sam enters it.
  void _create() {
    final madeAt = _now();
    world.makeCode(demoCode, madeAt, madeAt.add(PairingService.inviteLifetime));
    settle();
  }

  /// Connect on Sam's phone: her code sets the pair on its way to both
  /// phones; any other is refused in the app's own words and pairs nobody.
  void _connect(String typed) {
    final code = PairingService.normalizeCode(typed);
    if (code.isEmpty) return;
    _refused = !world.redeem(code);
    if (!_refused) {
      _focus.unfocus();
      send(GuidePhone.here);
      send(GuidePhone.there);
    }
    settle();
  }

  @override
  void dispose() {
    _field.dispose();
    _templateField.dispose();
    _focus.dispose();
    super.dispose();
  }
}
