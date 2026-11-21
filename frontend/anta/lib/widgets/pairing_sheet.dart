import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

import '../bloc/pairing/pairing_bloc.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/guide_book.dart';
import '../models/sync_guide_content.dart';
import '../services/app_navigator.dart';
import '../services/pairing_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/pairing_error.dart';
import 'automation_id.dart';
import 'form_rows.dart';
import 'pairing_sheet_parts.dart';

/// Opens the pairing flow over an existing [PairingBloc]. The sheet exists so
/// the Sharing page keeps one scannable row: a countdown, copy/share/cancel and
/// a validating code field do not belong in a settings list.
Future<void> showPairingSheet(BuildContext context, PairingBloc bloc) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    // The body scrolls, so the sheet can grow to the screen's height: its
    // handle and header stay below the status bar.
    useSafeArea: true,
    // The guide's page on pairing opens over the sheet from its header: the
    // sheet's nodes are read again once that page has gone, or a screen
    // reader aims at where its controls stood while the page slid away.
    builder: (_) => FormSheetSemanticsRefresh(
      child: BlocProvider<PairingBloc>.value(
        value: bloc,
        child: const _PairingSheet(),
      ),
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

  /// Whether the sheet already closed itself. "Paired" arrives more than
  /// once — first with the partner's uid alone, then with the name they
  /// publish — and the second arrival, while the sheet was still sliding
  /// away, popped the page under it: the redeemer landed on Settings.
  bool _closed = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // Keyboard when it is up, gesture bar when it is not: without the
    // viewPadding the Connect button sits under the home indicator. The
    // larger of the two, never their sum — the keyboard inset already
    // reaches down to the screen edge, so adding the system inset to it
    // floats the sheet a navigation bar above the keys.
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );

    return BlocConsumer<PairingBloc, PairingState>(
      listenWhen: (previous, current) =>
          current is PairingPaired || current is PairingUnavailable,
      listener: (context, state) {
        if (_closed) return;
        _closed = true;
        // Under the guide's page the sheet goes from beneath it: a pop
        // would take the page she is reading instead.
        final route = ModalRoute.of(context);
        if (route != null && !route.isCurrent) {
          Navigator.of(context).removeRoute(route);
          return;
        }
        Navigator.of(context).maybePop();
      },
      builder: (context, state) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FormSheetHandle(),
            // Live: a code is made and a pair is entered at once, so the ✕
            // only closes.
            FormSheetHeader(
              leadingIcon: Icons.close_rounded,
              leadingTooltip: l10n.close,
              onLeading: () => Navigator.of(context).maybePop(),
              title: l10n.pairingTitle,
              stackTitleAtLargeText: true,
              trailingInset: FormMetrics.headerActionInset,
              trailing: AutomationId(
                identifier: SemanticsIds.pairingHow,
                child: IconButton(
                  icon: const Icon(Icons.help_outline_rounded),
                  tooltip: l10n.syncGuideHowPairingWorks,
                  color: theme.colorScheme.onSurfaceVariant,
                  onPressed: () => _openGuide(context),
                ),
              ),
            ),
            // Everything under the header scrolls: at large text the stacked
            // header and the body together are taller than the screen above
            // the keys, and the field and Connect have to be reachable.
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + clearance),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ..._inviteSection(context, l10n, state),
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
                    _redeemSection(context, l10n, state, clearance),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The guide's page on pairing, over the sheet (D49): back returns here
  /// with the code made and anything typed as they were, since the sheet
  /// stays under the page. Focus drops first, or the return re-raises the
  /// keyboard.
  void _openGuide(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    AppNavigator.toGuideTopic(context, GuideBook.sync, SyncGuideTopic.pair);
  }

  List<Widget> _inviteSection(
    BuildContext context,
    AppLocalizations l10n,
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
      return [
        PairingCreateCodeButton(
          busy: _busy(state),
          onPressed: () =>
              context.read<PairingBloc>().add(const GenerateInviteRequested()),
        ),
        ?inviteError,
      ];
    }

    return [
      PairingCodeView(
        code: state.code,
        expiresAt: state.expiresAt,
        onCopy: () => _copy(context, l10n, state.code),
        actions: [
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

  /// [clearance] is what the keys cover of the scroll view: the field is
  /// brought above it when it takes focus, since the viewport itself runs
  /// on under the keys.
  Widget _redeemSection(
    BuildContext context,
    AppLocalizations l10n,
    PairingState state,
    double clearance,
  ) {
    final failure = _failureOf(state);
    return PairingCodeEntry(
      controller: _codeController,
      busy: _busy(state),
      errorText: failure == null || !failure.belongsToCodeField
          ? null
          : PairingErrorMessages.of(l10n).resolve(failure.error),
      errorMaxLines: FormMetrics.fieldErrorMaxLines,
      revealBelow: clearance,
      onSubmit: (value) => _redeem(context, value),
    );
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
