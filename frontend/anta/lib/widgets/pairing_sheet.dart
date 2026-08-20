import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

import '../bloc/pairing/pairing_bloc.dart';
import '../l10n/app_localizations.dart';
import '../services/pairing_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/pairing_error.dart';

/// Opens the pairing flow over an existing [PairingBloc]. The sheet exists so
/// the Sharing page keeps one scannable row: a countdown, copy/share/cancel and
/// a validating code field do not belong in a settings list.
Future<void> showPairingSheet(BuildContext context, PairingBloc bloc) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => BlocProvider<PairingBloc>.value(
      value: bloc,
      child: const _PairingSheet(),
    ),
  );
}

class _PairingSheet extends StatefulWidget {
  const _PairingSheet();

  @override
  State<_PairingSheet> createState() => _PairingSheetState();
}

class _PairingSheetState extends State<_PairingSheet> {
  final TextEditingController _codeController = TextEditingController();

  /// Mirrors the field so Connect can disable itself until a whole code is
  /// present — an enabled button that silently does nothing is worse than a
  /// disabled one that explains itself by being disabled.
  String _typedCode = '';

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return BlocConsumer<PairingBloc, PairingState>(
      listenWhen: (previous, current) =>
          current is PairingPaired || current is PairingUnavailable,
      listener: (context, state) => Navigator.of(context).maybePop(),
      builder: (context, state) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            // Keyboard when it is up, gesture bar when it is not: without the
            // viewPadding the Connect button sits under the home indicator.
            24 +
                MediaQuery.of(context).viewInsets.bottom +
                MediaQuery.of(context).viewPadding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(l10n.pairingTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: 20),
              ..._inviteSection(context, l10n, theme, state),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      l10n.pairingOr,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 20),
              ..._redeemSection(context, l10n, state),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _inviteSection(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    PairingState state,
  ) {
    final failure = _failureOf(state);
    // The page's snackbar renders behind this modal, so a failure that belongs
    // to the invite half has to be shown here or the tap looks like it did
    // nothing at all.
    final inviteError = failure != null && !failure.belongsToCodeField
        ? _errorText(context, l10n, failure.error)
        : null;

    if (state is! PairingInviting) {
      final busy = _busy(state);
      return [
        FilledButton.icon(
          onPressed: busy
              ? null
              : () => context.read<PairingBloc>().add(
                  const GenerateInviteRequested(),
                ),
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_link_rounded),
          label: Text(l10n.pairingGenerateCode),
        ),
        ?inviteError,
      ];
    }

    return [
      Text(
        l10n.pairingCodeIntro,
        style: theme.textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      SelectableText(
        PairingService.formatCode(state.code),
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontFamily: 'monospace',
          letterSpacing: 4,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      _Countdown(expiresAt: state.expiresAt),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton.icon(
            onPressed: () => _copy(context, l10n, state.code),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(l10n.copy),
          ),
          TextButton.icon(
            onPressed: () => SharePlus.instance.share(
              ShareParams(
                text: l10n.pairingShareMessage(
                  PairingService.formatCode(state.code),
                ),
              ),
            ),
            icon: const Icon(Icons.share_rounded, size: 18),
            label: Text(l10n.share),
          ),
          TextButton.icon(
            onPressed: state.busy
                ? null
                : () => context.read<PairingBloc>().add(
                    const CancelInviteRequested(),
                  ),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text(l10n.cancel),
          ),
        ],
      ),
      ?inviteError,
    ];
  }

  List<Widget> _redeemSection(
    BuildContext context,
    AppLocalizations l10n,
    PairingState state,
  ) {
    final failure = _failureOf(state);
    final busy = _busy(state);
    final complete =
        PairingService.normalizeCode(_typedCode).length ==
        PairingService.codeLength;

    return [
      TextField(
        controller: _codeController,
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.characters,
        maxLength: PairingService.codeLength + 1,
        style: const TextStyle(fontFamily: 'monospace', letterSpacing: 3),
        decoration: InputDecoration(
          labelText: l10n.pairingEnterCode,
          hintText: l10n.pairingCodeHint,
          border: const OutlineInputBorder(),
          counterText: '',
          // Inline, not a snackbar: the user is mid-correction and needs the
          // message to stay next to the field they are fixing. Only a
          // redemption failure belongs here — a failed "create a code" must
          // not put a red border on a field they never touched.
          errorText: failure == null || !failure.belongsToCodeField
              ? null
              : PairingErrorMessages.of(l10n).resolve(failure.error),
        ),
        onChanged: (value) => setState(() => _typedCode = value),
        onSubmitted: busy || !complete
            ? null
            : (value) => _redeem(context, value),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: busy || !complete
            ? null
            : () => _redeem(context, _codeController.text),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(l10n.pairingConnect),
      ),
    ];
  }

  PairingFailure? _failureOf(PairingState state) => switch (state) {
    PairingUnpaired(:final failure) => failure,
    PairingInviting(:final failure) => failure,
    PairingPaired(:final failure) => failure,
    _ => null,
  };

  Widget _errorText(
    BuildContext context,
    AppLocalizations l10n,
    PairingError error,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        PairingErrorMessages.of(l10n).resolve(error),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }

  void _redeem(BuildContext context, String value) {
    final code = PairingService.normalizeCode(value);
    if (code.isEmpty) return;
    context.read<PairingBloc>().add(RedeemCodeRequested(code));
  }

  Future<void> _copy(
    BuildContext context,
    AppLocalizations l10n,
    String code,
  ) async {
    await Clipboard.setData(
      ClipboardData(text: PairingService.formatCode(code)),
    );
    if (context.mounted) CustomSnackbar.show(context, l10n.pairingCodeCopied);
  }

  bool _busy(PairingState state) => switch (state) {
    PairingUnpaired(:final busy) => busy,
    PairingInviting(:final busy) => busy,
    PairingPaired(:final busy) => busy,
    _ => false,
  };
}

/// Owns its own ticker so the per-second rebuild is scoped to this one line of
/// text, instead of rebuilding the sheet's `TextField` under the user's cursor
/// once a second. Stops itself at expiry.
class _Countdown extends StatefulWidget {
  const _Countdown({required this.expiresAt});

  final DateTime expiresAt;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_Countdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expiresAt != widget.expiresAt) _start();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _start() {
    _ticker?.cancel();
    if (_remaining().isNegative) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {});
      if (_remaining().isNegative) timer.cancel();
    });
  }

  Duration _remaining() => widget.expiresAt.difference(DateTime.now().toUtc());

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
