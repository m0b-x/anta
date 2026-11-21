import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../bloc/share/share_bloc.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../constants/row_metrics.dart';
import '../l10n/app_localizations.dart';
import '../models/share_overview.dart';
import '../services/share_service.dart';
import 'form_rows.dart';

/// An Undo tapped once the surface that offered it has gone with its bloc —
/// a list sheet's, the Sharing page's, the browser's: it writes through
/// [ShareService.undo] itself, the one place a sharing surface acts past
/// its bloc, since nothing is left to act through. A failure is said on
/// [messenger] ([sayShareFailurePastSurface]).
///
/// Written in its turn by the service, which writes its share writes in the
/// order asked: the act it undoes, still writing, lands first. A database
/// switched before the service answered, or before the Undo's turn came,
/// is not the one it was tapped in, so it then writes nothing and says
/// nothing, as a tap after a switch does.
Future<void> undoSharePastBloc(
  ShareChange change, {
  required Future<ShareService> Function() shareService,
  required ScaffoldMessengerState? messenger,
  required AppLocalizations l10n,
}) async {
  final generation = ShareService.databaseGeneration;
  try {
    final service = await shareService();
    if (ShareService.databaseGeneration != generation) return;
    await service.undo(change);
  } on ShareRefused {
    sayShareFailurePastSurface(messenger, l10n.shareNeedsSync);
  } on ShareDatabaseSwitched {
    return;
  } catch (e, st) {
    debugPrint('[undoSharePastBloc] undo failed: $e\n$st');
    sayShareFailurePastSurface(messenger, l10n.shareChangeFailed);
  }
}

/// A share act's failure said once the surface that asked for it has gone:
/// on [messenger], the app's own captured while it stood, as a plain
/// floating bar — no context that has gone is read and no host Scaffold is
/// looked for, which over a bottom route that does not resize would reach
/// for an overlay from above it.
void sayShareFailurePastSurface(
  ScaffoldMessengerState? messenger,
  String failure,
) {
  // The app torn down with its messenger has nobody left to tell.
  if (messenger == null || !messenger.mounted) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(failure),
        behavior: SnackBarBehavior.floating,
        margin: AppSpacing.snackbarMargin(),
        duration: AppConstants.snackbarErrorDuration,
        showCloseIcon: true,
      ),
    );
}

/// How a share act's failure is said once its bloc closed before the act
/// started and wrote it past itself (`ShareActEvent.failedPastBloc`): on
/// [messenger], the app's own captured at the tap, in the words the
/// surface would have used.
void Function(ShareFailure failure) shareFailurePastSurface(
  ScaffoldMessengerState? messenger,
  AppLocalizations l10n,
) =>
    (failure) => sayShareFailurePastSurface(
      messenger,
      failure == ShareFailure.refused
          ? l10n.shareNeedsSync
          : l10n.shareChangeFailed,
    );

/// A list sheet dismissed while [pending] acts it asked for — those whose
/// `ShareActEvent.asker` is [asker] — had not answered: their outcomes are
/// heard on [bloc] past [seen], and a failure among them said on
/// [messenger]. The sheet that would have said it is gone, and neither the
/// page nor a sheet opened since answers for an act it did not ask for, so
/// this is the one voice. A success says nothing more: its words were said
/// at the tap.
void sayShareFailuresPastSheet({
  required ShareBloc bloc,
  required Object asker,
  required int pending,
  required int? seen,
  required ScaffoldMessengerState? messenger,
  required AppLocalizations l10n,
}) {
  if (pending <= 0 || bloc.isClosed) return;
  var left = pending;
  var last = seen;
  late final StreamSubscription<ShareState> subscription;
  subscription = bloc.stream.listen((state) {
    final outcome = state is ShareLoaded ? state.outcome : null;
    if (outcome == null || outcome.sequence == last) return;
    last = outcome.sequence;
    if (!identical(outcome.asker, asker)) return;
    switch (outcome.failure) {
      case ShareFailure.refused:
        sayShareFailurePastSurface(messenger, l10n.shareNeedsSync);
      case ShareFailure.failed:
        sayShareFailurePastSurface(messenger, l10n.shareChangeFailed);
      case null:
        break;
    }
    if (--left == 0) unawaited(subscription.cancel());
  });
}

/// The filler box the Sharing page's lists open in — the shared events and
/// the shared folders, mine and the partner's: the editor's fixed height,
/// the route's own drag, nothing to guard — every ✕ writes at once.
Future<void> showShareListSheet(BuildContext context, Widget sheet) {
  final colorScheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
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
    // A row opens its event, or the folder picker, above the list, and may
    // do so while the list is still sliding in: its nodes are read again
    // once that route has gone.
    builder: (_) => FormSheetSemanticsRefresh(
      child: FractionallySizedBox(
        heightFactor: FormMetrics.sheetHeightFactor,
        child: sheet,
      ),
    ),
  );
}

/// The share lists' one frame: handle, a header with ✕ and no action — a
/// list that writes at once has nothing to confirm — the optional caption
/// pinned under it, and the rows, or the one line that says there are none.
///
/// [footer] rows end the same group after the data rows — "Share a folder"
/// — and stand in a group of their own under the empty line when there are
/// no rows, so the way to add is never gone with the last row.
class ShareListFrame extends StatelessWidget {
  final String identifier;
  final String title;
  final String? caption;
  final String empty;
  final List<Widget> rows;
  final List<Widget> footer;

  const ShareListFrame({
    super.key,
    required this.identifier,
    required this.title,
    required this.empty,
    required this.rows,
    this.caption,
    this.footer = const [],
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    final caption = this.caption;
    final emptyLine = FormCaption(
      text: empty,
      padding: FormMetrics.groupCaptionPadding,
    );
    return Semantics(
      container: true,
      identifier: identifier,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormSheetHandle(),
          FormSheetHeader(
            leadingIcon: Icons.close_rounded,
            leadingTooltip: l10n.close,
            onLeading: () => Navigator.of(context).pop(),
            title: title,
            // A heading, as the read sheet's: a screen reader's headings
            // list then holds every share sheet by its name.
            titleIsHeading: true,
            trailingInset: FormMetrics.headerActionInset,
            trailing: const SizedBox.shrink(),
            stackTitleAtLargeText: true,
          ),
          if (caption != null)
            FormCaption(
              text: caption,
              padding: const EdgeInsets.fromLTRB(
                RowMetrics.groupInset,
                0,
                RowMetrics.groupInset,
                FormMetrics.headerCaptionBottomPadding,
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                RowMetrics.groupInset,
                FormMetrics.bodyTop,
                RowMetrics.groupInset,
                FormMetrics.bodyBottom + clearance,
              ),
              child: switch ((rows.isEmpty, footer.isEmpty)) {
                (true, true) => emptyLine,
                (true, false) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    emptyLine,
                    FormRowGroup(trailingGap: false, children: footer),
                  ],
                ),
                (false, _) => FormRowGroup(
                  trailingGap: false,
                  children: [...rows, ...footer],
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}
