import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../services/pairing_service.dart';
import 'automation_id.dart';

// The pairing sheet's body, as pure widgets the sheet and the sync guide's
// `pair` stage both draw (`docs/guide-hub-roadmap.md` D43): they read no
// bloc and write nothing, so the guide can never drift from the sheet. The
// caller holds the state and answers the callbacks; every id defaults to
// the sheet's own, and a stage passes its card's.

/// "Create a code": the invite half before a code exists. [busy] shows the
/// spinner in the glyph's place and holds the button.
class PairingCreateCodeButton extends StatelessWidget {
  const PairingCreateCodeButton({
    super.key,
    required this.busy,
    required this.onPressed,
    this.identifier = SemanticsIds.pairingGenerate,
  });

  final bool busy;
  final VoidCallback onPressed;
  final String identifier;

  @override
  Widget build(BuildContext context) {
    return AutomationId(
      identifier: identifier,
      child: FilledButton.icon(
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_link_rounded),
        label: Text(AppLocalizations.of(context)!.pairingGenerateCode),
      ),
    );
  }
}

/// A code made: what to do with it, the code as [PairingService.formatCode]
/// writes it, how long it is good for, and Copy — then [actions], the
/// sheet's Share and Cancel, in the same row, or stacked under it in that
/// order when the row does not fit.
///
/// [heldAt] holds the countdown still at the life left at that moment, for
/// a stage that must not tick the clock for real; null, it counts down from
/// the wall clock as the sheet's does.
class PairingCodeView extends StatelessWidget {
  const PairingCodeView({
    super.key,
    required this.code,
    required this.expiresAt,
    required this.onCopy,
    this.heldAt,
    this.actions = const [],
    this.codeIdentifier = SemanticsIds.pairingCode,
    this.copyIdentifier,
    this.selectable = true,
  });

  /// The code as stored, before formatting.
  final String code;
  final DateTime expiresAt;
  final DateTime? heldAt;

  /// Whether the code can be selected and copied by hand. A stage copies
  /// nothing, so its code is plain text.
  final bool selectable;
  final VoidCallback onCopy;
  final List<Widget> actions;
  final String codeIdentifier;
  final String? copyIdentifier;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final formatted = PairingService.formatCode(code);
    final codeStyle = theme.textTheme.headlineSmall?.copyWith(
      fontFamily: 'monospace',
      letterSpacing: 4,
      fontWeight: FontWeight.w600,
    );
    final Widget copy = TextButton.icon(
      onPressed: onCopy,
      icon: const Icon(Icons.copy_rounded, size: 18),
      label: Text(l10n.copy),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.pairingCodeIntro,
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        AutomationId(
          identifier: codeIdentifier,
          // One line, scaled down when the width is short: a code broken
          // mid-code at large text reads as two.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: selectable
                ? SelectableText(formatted, maxLines: 1, style: codeStyle)
                : Text(
                    formatted,
                    maxLines: 1,
                    softWrap: false,
                    style: codeStyle,
                  ),
          ),
        ),
        const SizedBox(height: 4),
        PairingCountdown(expiresAt: expiresAt, heldAt: heldAt),
        const SizedBox(height: 12),
        // Stacked, in the same order, once the three do not fit one row:
        // German does not fit a 360 phone at any text scale.
        OverflowBar(
          alignment: MainAxisAlignment.center,
          overflowAlignment: OverflowBarAlignment.center,
          children: [
            if (copyIdentifier case final id?)
              AutomationId(identifier: id, child: copy)
            else
              copy,
            ...actions,
          ],
        ),
      ],
    );
  }
}

/// Owns its own ticker so the per-second rebuild is scoped to this one line of
/// text, instead of rebuilding the sheet's `TextField` under the user's cursor
/// once a second. Stops itself at expiry. With [heldAt] it never ticks: it
/// says the life left at that moment and holds it.
class PairingCountdown extends StatefulWidget {
  const PairingCountdown({super.key, required this.expiresAt, this.heldAt});

  final DateTime expiresAt;
  final DateTime? heldAt;

  @override
  State<PairingCountdown> createState() => _PairingCountdownState();
}

class _PairingCountdownState extends State<PairingCountdown> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(PairingCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expiresAt != widget.expiresAt ||
        oldWidget.heldAt != widget.heldAt) {
      _start();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _start() {
    _ticker?.cancel();
    _ticker = null;
    if (widget.heldAt != null || _remaining().isNegative) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {});
      if (_remaining().isNegative) timer.cancel();
    });
  }

  Duration _remaining() => widget.expiresAt.difference(
    widget.heldAt?.toUtc() ?? DateTime.now().toUtc(),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final remaining = _remaining();
    final expired = remaining.isNegative || remaining == Duration.zero;
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;

    return Text(
      expired
          ? l10n.pairingCodeExpired
          : l10n.pairingCodeExpiresIn(
              '$minutes:${seconds.toString().padLeft(2, '0')}',
            ),
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        color: expired
            ? theme.colorScheme.error
            : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// The redeem half: the field a code is typed in — upper case, no
/// suggestions, [PairingService.codeLength] characters and a dash — and
/// Connect.
///
/// Connect, and the keyboard's submit, wait for a whole code: an enabled
/// button that silently does nothing is worse than a disabled one that
/// explains itself by being disabled. [onSubmit] is handed the field's text
/// as typed.
class PairingCodeEntry extends StatefulWidget {
  const PairingCodeEntry({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.errorText,
    this.errorMaxLines,
    this.busy = false,
    this.focusNode,
    this.revealBelow,
    this.fieldIdentifier = SemanticsIds.pairingCodeField,
    this.connectIdentifier = SemanticsIds.pairingConnect,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  /// Inline, not a snackbar: the user is mid-correction and needs the
  /// message to stay next to the field they are fixing. Only a redemption
  /// failure belongs here — a failed "create a code" must not put a red
  /// border on a field they never touched.
  final String? errorText;

  /// Null keeps the decorator's one line, which cuts a refusal on a phone's
  /// width: the sheet and the stage both pass a bound.
  final int? errorMaxLines;
  final bool busy;
  final FocusNode? focusNode;

  /// How much of the scroll view around the field the keyboard covers. A
  /// sheet's viewport runs on under the keys, so a field revealed into it
  /// alone can stay hidden: the field is revealed this much higher, with
  /// Connect under it — the button that finishes the field. Null, the
  /// field is revealed as any field is.
  final double? revealBelow;
  final String fieldIdentifier;
  final String connectIdentifier;

  @override
  State<PairingCodeEntry> createState() => _PairingCodeEntryState();
}

class _PairingCodeEntryState extends State<PairingCodeEntry> {
  /// `TextField`'s own default, which [PairingCodeEntry.revealBelow] adds to.
  static const EdgeInsets _revealPadding = EdgeInsets.all(20);

  /// Between the field and Connect.
  static const double _connectGap = 12;

  final GlobalKey _connectKey = GlobalKey();

  /// Connect's height as last laid out. It changes with the text scale and
  /// the spinner, so it is read off the layout rather than worked out.
  double _connectHeight = 0;

  void _measureConnect(Duration _) {
    if (!mounted) return;
    final height = _connectKey.currentContext?.size?.height;
    if (height == null || height == _connectHeight) return;
    setState(() => _connectHeight = height);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final revealBelow = widget.revealBelow;
    if (revealBelow != null) {
      WidgetsBinding.instance.addPostFrameCallback(_measureConnect);
    }
    final scrollPadding = revealBelow == null
        ? _revealPadding
        : _revealPadding.copyWith(
            bottom:
                _revealPadding.bottom +
                revealBelow +
                _connectGap +
                _connectHeight,
          );
    final controller = widget.controller;
    final busy = widget.busy;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final complete =
            PairingService.normalizeCode(controller.text).length ==
            PairingService.codeLength;
        final canSubmit = !busy && complete;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AutomationId(
              identifier: widget.fieldIdentifier,
              child: TextField(
                controller: controller,
                focusNode: widget.focusNode,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                maxLength: PairingService.codeLength + 1,
                scrollPadding: scrollPadding,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  letterSpacing: 3,
                ),
                decoration: InputDecoration(
                  labelText: l10n.pairingEnterCode,
                  hintText: l10n.pairingCodeHint,
                  border: const OutlineInputBorder(),
                  counterText: '',
                  errorText: widget.errorText,
                  errorMaxLines: widget.errorMaxLines,
                ),
                onSubmitted: canSubmit ? widget.onSubmit : null,
              ),
            ),
            const SizedBox(height: _connectGap),
            AutomationId(
              identifier: widget.connectIdentifier,
              child: FilledButton(
                key: _connectKey,
                onPressed: canSubmit
                    ? () => widget.onSubmit(controller.text)
                    : null,
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.pairingConnect),
              ),
            ),
          ],
        );
      },
    );
  }
}
