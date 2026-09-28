import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../constants/app_colors.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/alert_sound.dart';
import '../services/alert_gateway.dart';
import 'form_rows.dart';

/// What the chooser reports back. `null` from [AlertSoundSheet.show] means the
/// sheet was dismissed without deciding anything — which is *not* the same as
/// [AlertSoundPicked] carrying a null value, the deliberate "use the app
/// setting".
sealed class AlertSoundResult {
  const AlertSoundResult();
}

/// A sound was chosen. [value] is exactly what the caller should persist, in
/// the one encoding [AlertSound] reads back.
class AlertSoundPicked extends AlertSoundResult {
  final String? value;

  /// The phone's own name for it, when the picker just said so. Never
  /// persisted — a phone's name for a sound is the phone's to change — but it
  /// saves the row that opened this sheet a round trip before it can redraw.
  final String? title;

  const AlertSoundPicked(this.value, {this.title});
}

/// The device turned out to have no sound picker at all.
///
/// Reported rather than shown here: a `SnackBar` belongs to a `Scaffold`, which
/// sits *below* a modal route, so one raised from inside this sheet would be
/// painted behind it. The caller shows it once this has closed.
class AlertSoundPickerMissing extends AlertSoundResult {
  const AlertSoundPickerMissing();
}

/// The one alarm-sound chooser, shared by the alert editor and the Calendar
/// settings row so the two cannot offer different vocabularies for the same
/// stored value.
///
/// Radio-style, and everything it offers is a value [AlertSound] can encode.
/// The phone's picker is hidden outright where the platform has none
/// ([AlertGateway.supportsSoundPicker]) rather than offered and then failing;
/// a value that *names* a picked sound is still shown as chosen, because it is
/// what the row says even on a device that cannot resolve it.
///
/// **No preview player.** The system picker previews every sound it offers
/// while the user scrolls it, so a second one here would be a second audio
/// session fighting the first.
class AlertSoundSheet extends StatefulWidget {
  /// The value as it is stored today — `null` for "follow the app setting".
  final String? value;

  /// Whether "Use the app setting" is one of the choices. True in the alert
  /// editor, where an alert may defer; false on the settings row, which *is*
  /// the app setting and has nothing to defer to.
  final bool allowInherit;

  const AlertSoundSheet({
    super.key,
    required this.value,
    this.allowInherit = false,
  });

  static Future<AlertSoundResult?> show(
    BuildContext context, {
    required String? value,
    bool allowInherit = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<AlertSoundResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: colorScheme.pageGround,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FormMetrics.sheetRadius),
        ),
      ),
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height * FormMetrics.sheetHeightFactor,
        ),
        child: AlertSoundSheet(value: value, allowInherit: allowInherit),
      ),
    );
  }

  /// The one-line label a stored value reads as, for the row that opens this.
  ///
  /// [title] is the phone's own name where it is known; a picked sound whose
  /// title could not be resolved is named as unavailable rather than by its
  /// raw URI, which says nothing to anyone.
  static String labelFor(
    AppLocalizations l10n,
    String? value, {
    String? title,
    bool titleResolved = false,
  }) {
    return switch (AlertSound.decode(value)) {
      AlertSoundInherit() => l10n.alertSoundUseAppSetting,
      AlertSoundSystemDefault() => title ?? l10n.alertSoundPhoneDefault,
      AlertSoundUri() =>
        title ??
            (titleResolved
                ? l10n.alertSoundUnavailable
                : l10n.alertSoundFromPhone),
    };
  }

  @override
  State<AlertSoundSheet> createState() => _AlertSoundSheetState();
}

class _AlertSoundSheetState extends State<AlertSoundSheet> {
  late String? _value;

  /// The phone's name for the currently stored picked sound, and whether the
  /// question has been answered at all. The two are separate because `null`
  /// after an answer means "this device cannot resolve it", which is the copy
  /// that matters.
  String? _title;
  bool _titleResolved = false;

  /// True while the system picker is up, so a second tap cannot open a second
  /// one — the platform refuses that anyway, and refusing it here is quieter.
  bool _picking = false;

  /// The body's scroll position feeds the header's hairline (a sub-sheet's
  /// rule): a notifier, never `setState`, so a scroll frame rebuilds a 1 px
  /// line and not the rows.
  final ScrollController _bodyScroll = ScrollController();
  final ValueNotifier<bool> _headerScrolled = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _value = widget.value;
    _bodyScroll.addListener(_onBodyScroll);
    _resolveTitle();
  }

  @override
  void dispose() {
    _bodyScroll.removeListener(_onBodyScroll);
    _bodyScroll.dispose();
    _headerScrolled.dispose();
    super.dispose();
  }

  void _onBodyScroll() {
    final scrolled = _bodyScroll.hasClients && _bodyScroll.offset > 0;
    if (_headerScrolled.value != scrolled) _headerScrolled.value = scrolled;
  }

  AlertGateway? get _gateway =>
      GetIt.I.isRegistered<AlertGateway>() ? GetIt.I<AlertGateway>() : null;

  bool get _supportsSoundPicker => _gateway?.supportsSoundPicker ?? false;

  /// Asks the phone what it calls the stored sound, once, without blocking the
  /// first frame. Best-effort: a build with no gateway simply never answers,
  /// and the row keeps its neutral label.
  Future<void> _resolveTitle() async {
    final value = _value;
    if (value == null || AlertSound.decode(value) is! AlertSoundUri) return;
    final gateway = _gateway;
    if (gateway == null) return;
    final title = await gateway.soundTitle(value);
    if (!mounted) return;
    setState(() {
      _title = title;
      _titleResolved = true;
    });
  }

  void _choose(String? value, {String? title}) {
    Navigator.of(context).pop(AlertSoundPicked(value, title: title));
  }

  Future<void> _pickFromPhone() async {
    final gateway = _gateway;
    if (gateway == null || _picking) return;
    setState(() => _picking = true);
    try {
      final picked = await gateway.pickSystemSound(_value);
      if (!mounted) return;
      // A cancelled pick is a decision too: the sheet stays exactly where it
      // was rather than closing on a choice nobody made.
      if (picked == null) {
        setState(() => _picking = false);
        return;
      }
      _choose(picked.value, title: picked.title);
    } on AlertSoundPickerUnavailable {
      if (!mounted) return;
      Navigator.of(context).pop(const AlertSoundPickerMissing());
    } catch (_) {
      if (!mounted) return;
      setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // `useSafeArea: true` guards the status bar, not the bottom gesture/nav
    // bar, so the rows pad by the larger of the keyboard inset and the
    // system inset — the sub-sheet rule.
    final bottomClearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    final current = AlertSound.decode(_value);

    // Exclusive check rows rather than `Radio`s: the list mixes a plain
    // choice with one that opens another activity, and the group value is a
    // *decoded* sound rather than any one stored string.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.cancel,
          leadingIdentifier: SemanticsIds.soundClose,
          onLeading: () => Navigator.of(context).pop(),
          title: l10n.alertsSound,
          scrolled: _headerScrolled,
          trailingInset: FormMetrics.headerActionInset,
          // A row pops on tap; there is nothing to confirm.
          trailing: const SizedBox.shrink(),
        ),
        Flexible(
          child: SingleChildScrollView(
            controller: _bodyScroll,
            padding: EdgeInsets.fromLTRB(
              RowMetrics.groupInset,
              FormMetrics.bodyTop,
              RowMetrics.groupInset,
              FormMetrics.bodyBottom + bottomClearance,
            ),
            child: FormRowGroup(
              trailingGap: false,
              children: [
                if (widget.allowInherit)
                  FormCheckRow(
                    exclusive: true,
                    glyph: Icons.settings_suggest_outlined,
                    label: l10n.alertSoundUseAppSetting,
                    checked: current is AlertSoundInherit,
                    identifier: SemanticsIds.soundInherit,
                    onChanged: (_) => _choose(null),
                  ),
                FormCheckRow(
                  exclusive: true,
                  glyph: Icons.phone_android_rounded,
                  label: l10n.alertSoundPhoneDefault,
                  checked: current is AlertSoundSystemDefault,
                  identifier: SemanticsIds.soundPhoneDefault,
                  onChanged: (_) => _choose(AlertSound.systemDefaultValue),
                ),
                if (_supportsSoundPicker)
                  FormCheckRow(
                    exclusive: true,
                    glyph: Icons.library_music_outlined,
                    label: l10n.alertSoundChooseFromPhone,
                    // Reserved the moment a picked sound is what is stored,
                    // and only then: the line is filled with a neutral name
                    // first and swapped for the phone's own, so the row never
                    // changes height.
                    caption: current is AlertSoundUri
                        ? AlertSoundSheet.labelFor(
                            l10n,
                            _value,
                            title: _title,
                            titleResolved: _titleResolved,
                          )
                        : null,
                    checked: current is AlertSoundUri,
                    identifier: SemanticsIds.soundFromPhone,
                    onChanged: _picking ? null : (_) => _pickFromPhone(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
