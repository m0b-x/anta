import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../constants/app_spacing.dart';
import '../l10n/app_localizations.dart';
import '../models/alert_sound.dart';
import '../services/alert_gateway.dart';

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
/// The phone's own two options are hidden outright where the platform cannot
/// serve them ([AlertGateway.supportsSystemSounds]) rather than offered and
/// then failing; a value that *names* one is still shown as chosen, because it
/// is what the row says even on a device that cannot resolve it.
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
    return showModalBottomSheet<AlertSoundResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          AlertSoundSheet(value: value, allowInherit: allowInherit),
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
      AlertSoundBundled() => l10n.alertSoundBundled,
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

  @override
  void initState() {
    super.initState();
    _value = widget.value;
    _resolveTitle();
  }

  AlertGateway? get _gateway =>
      GetIt.I.isRegistered<AlertGateway>() ? GetIt.I<AlertGateway>() : null;

  bool get _supportsSystemSounds => _gateway?.supportsSystemSounds ?? false;

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
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;
    final current = AlertSound.decode(_value);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(0, 0, 0, AppSpacing.lg + bottomClearance),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(l10n.alertsSound, style: theme.textTheme.titleLarge),
          ),
          if (widget.allowInherit)
            _SoundOptionTile(
              icon: Icons.settings_suggest_outlined,
              label: l10n.alertSoundUseAppSetting,
              selected: current is AlertSoundInherit,
              onTap: () => _choose(null),
            ),
          _SoundOptionTile(
            icon: Icons.album_outlined,
            label: l10n.alertSoundBundled,
            selected: current is AlertSoundBundled,
            onTap: () => _choose(''),
          ),
          if (_supportsSystemSounds) ...[
            _SoundOptionTile(
              icon: Icons.phone_android_rounded,
              label: l10n.alertSoundPhoneDefault,
              selected: current is AlertSoundSystemDefault,
              onTap: () => _choose(AlertSound.systemDefaultValue),
            ),
            _SoundOptionTile(
              icon: Icons.library_music_outlined,
              label: l10n.alertSoundChooseFromPhone,
              // Reserved the moment a picked sound is what is stored, and only
              // then: the line is filled with a neutral name first and swapped
              // for the phone's own, so the row never changes height.
              sublabel: current is AlertSoundUri
                  ? AlertSoundSheet.labelFor(
                      l10n,
                      _value,
                      title: _title,
                      titleResolved: _titleResolved,
                    )
                  : null,
              selected: current is AlertSoundUri,
              onTap: _picking ? null : _pickFromPhone,
            ),
          ],
        ],
      ),
    );
  }
}

/// One radio-shaped choice.
///
/// A `ListTile` with a drawn radio glyph rather than a `RadioListTile`: the
/// list mixes a plain choice with one that opens another activity, and the
/// group value is a *decoded* sound rather than any one stored string.
class _SoundOptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sublabel;
  final bool selected;
  final VoidCallback? onTap;

  const _SoundOptionTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      title: Text(label),
      subtitle: sublabel == null ? null : Text(sublabel!),
      trailing: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      selected: selected,
      onTap: onTap,
    );
  }
}
