import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_bar_metrics.dart';
import '../constants/form_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/guide_book.dart';
import '../services/app_navigator.dart';
import '../services/sync/sync_cadence.dart';
import '../services/sync/sync_gateway.dart';
import '../services/sync/sync_status.dart';
import '../utils/sync_moment_format.dart';
import 'automation_id.dart';
import 'form_rows.dart' show FormCaptionSlot;
import 'settings_section_list.dart';

/// The Sync section's rows a database's sync is turned on and read by — the
/// unbound "Sync this database" row, the status row and Sync now — drawn by
/// the Sync & sharing page and by the sync guide's stages
/// (`docs/guide-hub-roadmap.md` D43) from one place, so the guide can never
/// drift from the screen.
///
/// Pure: they read no bloc and write nothing; the caller holds the status
/// and answers the callbacks. Their `identifier` gives a row's id by name —
/// `bind`, `status`, `now` — for a stage, whose ids are its card's; null
/// keeps the page's own.
typedef SyncRowIdentifier = String Function(String row);

/// A count as wide as any the outbox reaches, for the templates that size
/// the status row: sized for it once, the row never grows when a count
/// appears or gains a digit.
const int syncCountTemplate = 99999;

/// A time of day as wide as the quota pause's usually is, in either clock,
/// for the templates.
const TimeOfDay _quotaTimeTemplate = TimeOfDay(hour: 22, minute: 58);

/// "Sync this database", the one row of an unbound database. Its
/// description slot fits the three fixed descriptions, so a sign-in, a
/// check or a failure moves nothing below (final review D-5): a failure's
/// reason or the heal's note ellipsizes inside it — the snackbar says a
/// failure whole. [row] draws the tile around the title and that slot: the
/// page's follows its bloc's flow, a stage's is a [SyncBindTile].
SettingsEntry syncThisDatabaseEntry(
  AppLocalizations l10n, {
  required String description,
  required Widget Function(BuildContext context, Widget title, Widget slot) row,
  List<String> keywords = const [],
  SyncRowIdentifier? identifier,
}) {
  return SettingsEntry(
    title: l10n.syncThisDatabase,
    description: description,
    keywords: keywords,
    identifier: identifier?.call('bind') ?? SemanticsIds.sharingSync,
    builder: (context, title, description) => row(
      context,
      title,
      SyncFixedLinesSlot(
        templates: [
          l10n.syncThisDatabaseDesc,
          l10n.syncSignInFirst,
          l10n.syncThisDatabaseUnavailable,
        ],
        child: description!,
      ),
    ),
  );
}

/// The unbound row's tile while it can be used: its glyph — a spinner while
/// [busy], the error glyph after a failed bind or stop — then the title over
/// the description. [onTap] null while busy: the text stays, so the row
/// keeps its height.
class SyncBindTile extends StatelessWidget {
  const SyncBindTile({
    super.key,
    required this.title,
    required this.description,
    required this.onTap,
    this.busy = false,
    this.failed = false,
  });

  final Widget title;
  final Widget? description;
  final VoidCallback? onTap;
  final bool busy;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SyncBusyValue(
      busy: busy,
      child: ListTile(
        leading: busy
            ? const SyncRowBusyIndicator()
            : Icon(
                failed
                    ? Icons.error_outline_rounded
                    : Icons.cloud_sync_outlined,
                color: failed ? colorScheme.error : colorScheme.primary,
              ),
        title: title,
        subtitle: description,
        onTap: onTap,
      ),
    );
  }
}

/// The Pairing section's row while a pair can be made — "Not paired", or
/// "Waiting for your partner" over the code — drawn by Sync & sharing and by
/// the sync guide's `pair` stage (D43). [busy] puts the spinner in the
/// glyph's place. [onTap] opens the pairing sheet on the page; a stage,
/// whose sheet's body stands under the row, passes null.
class PairingInviteTile extends StatelessWidget {
  const PairingInviteTile({
    super.key,
    required this.title,
    required this.description,
    required this.onTap,
    this.busy = false,
  });

  final Widget title;
  final Widget? description;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              Icons.link_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
      title: title,
      subtitle: description,
      onTap: onTap,
    );
  }
}

/// The Pairing section's row while paired — a page's row now: Unpair moved
/// onto the Sharing page it opens, so no action word yields under the
/// description. [avatar] is the partner's face, the link glyph while no
/// profile has arrived. The description, what is shared, sits in a slot as
/// tall as the widest of [summaryTemplates]; a failure's reason ([failed])
/// is the one description left free to wrap, as it was before the summary.
/// [onTap] opens the Sharing page; a stage passes null.
class PairedTile extends StatelessWidget {
  const PairedTile({
    super.key,
    required this.title,
    required this.description,
    required this.summaryTemplates,
    required this.onTap,
    this.avatar,
    this.busy = false,
    this.failed = false,
  });

  final Widget title;
  final Widget? description;
  final List<String> summaryTemplates;
  final VoidCallback? onTap;
  final Widget? avatar;
  final bool busy;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final description = this.description;
    return ListTile(
      enabled: !busy,
      leading: busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : avatar ??
                Icon(
                  Icons.link_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
      title: title,
      subtitle: !failed && description != null
          ? SyncFixedLinesSlot(templates: summaryTemplates, child: description)
          : description,
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

/// The help button in the bar of Sync & sharing and of the Sharing page
/// (D49), opening the sync book's hub, where the "Your setup" checklist
/// stands; one builder, so the two pages cannot drift. In the bar, not the
/// list: each page's list is pinned to end with its held-back and deletion
/// sections (review H2), and a guide stage that draws a section from this
/// file's builders never has a bar, so a guide page never links to itself.
Widget syncGuideHelpButton(BuildContext context, {required String identifier}) {
  return AutomationId(
    identifier: identifier,
    child: IconButton(
      icon: const Icon(Icons.help_outline_rounded),
      iconSize: AppBarMetrics.glyphSize,
      tooltip: AppLocalizations.of(context)!.syncGuideHowSyncWorks,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      onPressed: () => AppNavigator.toGuideBook(context, GuideBook.sync),
    ),
  );
}

/// The status row of a bound database: the line [syncStatusLine] says over
/// the details — the last sync, the rows held back, then the changes
/// waiting unless the line already counts them (review D2-3; held back said
/// nowhere else, so before what an ellipsis cuts first, RC3b-3). [now] is
/// the clock the details and the quota pause read, the wall clock unless a
/// stage keeps its own.
///
/// Sync now and Stop sit under this row, so it is as tall in every state as
/// the tallest line it may say over one details line: a run starting or a
/// count appearing moves nothing. The line and the details share one slot,
/// so the room a short state leaves falls under its last line, not between
/// the two (final review D-1), and the glyph stays on the line it labels.
SettingsEntry syncStatusEntry(
  BuildContext context,
  AppLocalizations l10n, {
  required SyncStatus status,
  List<String> keywords = const [],
  SyncRowIdentifier? identifier,
  DateTime? now,
}) {
  final (line, glyph, carriesCount) = syncStatusLine(
    context,
    l10n,
    status,
    now: now,
  );
  final lastSync = status.lastSyncAt;
  final details = [
    lastSync == null
        ? l10n.syncNeverSynced
        : l10n.syncLastSynced(formatSyncMoment(context, lastSync, now: now)),
    if (status.parkedCount > 0) l10n.syncParkedCount(status.parkedCount),
    if (status.pendingCount > 0 && !carriesCount)
      l10n.syncDetailsWaiting(status.pendingCount),
  ].join(' · ');
  return SettingsEntry(
    title: line,
    description: details,
    keywords: keywords,
    identifier: identifier?.call('status') ?? SemanticsIds.sharingSyncStatus,
    builder: (context, title, description) => ListTile(
      titleAlignment: ListTileTitleAlignment.top,
      leading: Icon(
        glyph,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: SyncStatusLines(
        templates: syncStatusLineTemplates(context, l10n),
        line: line,
        title: title,
        details: description!,
      ),
    ),
  );
}

/// "Sync now": asks the engine for a run at once. [enabled] by the page's
/// rule — signed in, no pause a run cannot end, nothing running, no step.
SettingsEntry syncNowEntry(
  AppLocalizations l10n, {
  required bool enabled,
  required VoidCallback onTap,
  List<String> keywords = const [],
  SyncRowIdentifier? identifier,
}) {
  return SettingsEntry(
    title: l10n.syncNow,
    keywords: keywords,
    identifier: identifier?.call('now') ?? SemanticsIds.sharingSyncNow,
    // The group's glyphs all sit on their first line, so a title that wraps
    // at 2.0 reads as the status row's does (review D2-8).
    builder: (context, title, description) {
      final colorScheme = Theme.of(context).colorScheme;
      return ListTile(
        titleAlignment: ListTileTitleAlignment.top,
        enabled: enabled,
        leading: Icon(
          Icons.sync_rounded,
          color: enabled
              ? colorScheme.primary
              : colorScheme.onSurface.withValues(
                  alpha: FormMetrics.disabledOpacity,
                ),
        ),
        title: title,
        onTap: onTap,
      );
    },
  );
}

/// Everything the status row's title may say, at one count and at
/// [syncCountTemplate], laid out unseen under the line it says now — the
/// quota pause at [_quotaTimeTemplate], wider than most times it says.
List<String> syncStatusLineTemplates(
  BuildContext context,
  AppLocalizations l10n,
) => [
  l10n.syncPausedQuotaUntil(formatSyncTimeOfDay(context, _quotaTimeTemplate)),
  l10n.syncPausedQuota,
  l10n.syncPausedSignedOut,
  l10n.syncPausedOtherAccount,
  l10n.syncPausedAppOutdated,
  l10n.syncPausedNoAccess,
  l10n.syncPausedSpaceDeleted,
  for (final count in const [1, syncCountTemplate]) ...[
    l10n.syncSending(count),
    l10n.syncDownloading(count),
    l10n.syncPendingCount(count),
    l10n.syncUpdatingNotes(count, count),
    l10n.syncUpdatingSending(count, count),
  ],
  l10n.syncUpdating,
  l10n.syncReceiving,
  l10n.syncOffline,
  l10n.syncRetrying,
  l10n.syncOfflineManual,
  l10n.syncFailedManual,
  l10n.syncManualIdle,
  l10n.syncUpToDate,
  l10n.syncWaitingFirst,
];

/// The one line that says what sync is doing, its glyph, and whether the
/// line already counts the pending changes the details would repeat. A
/// pause outranks a run, and a run the last failure it will retry. [now]
/// is the clock the quota pause's end is judged by.
(String, IconData, bool) syncStatusLine(
  BuildContext context,
  AppLocalizations l10n,
  SyncStatus status, {
  DateTime? now,
}) {
  const paused = Icons.pause_circle_outline_rounded;
  // Under the manual cadence nothing retries by itself and nothing keeps
  // the device current between presses, so the failure lines promise no
  // retry, the quota pause names no time it will resume at, and the idle
  // line says how a sync happens rather than "Up to date", which a week
  // later would still read so (record §13).
  final manual = status.cadence == SyncCadence.manual;
  switch (status.pause) {
    case SyncPause.quotaExhausted:
      final reset = manual
          ? null
          : status.quotaResetAfter(now ?? DateTime.now());
      return (
        reset == null
            ? l10n.syncPausedQuota
            : l10n.syncPausedQuotaUntil(formatSyncQuotaReset(context, reset)),
        paused,
        false,
      );
    case SyncPause.signedOut:
      return (l10n.syncPausedSignedOut, paused, false);
    case SyncPause.accountMismatch:
      return (l10n.syncPausedOtherAccount, paused, false);
    case SyncPause.appOutdated:
      return (l10n.syncPausedAppOutdated, paused, false);
    case SyncPause.noAccess:
      return (l10n.syncPausedNoAccess, paused, false);
    case SyncPause.spaceDeleted:
      return (l10n.syncPausedSpaceDeleted, paused, false);
    case SyncPause.none:
      break;
  }
  switch (status.activity) {
    case SyncActivity.pushing:
      if (syncUpdatingText(l10n, status) case final updating?) {
        return (updating, Icons.cloud_upload_outlined, false);
      }
      return (
        l10n.syncSending(status.pendingCount),
        Icons.cloud_upload_outlined,
        true,
      );
    // A count only the initial download after a bind and the re-read of
    // the notes after a wire update keep: an ordinary pull is over too fast
    // for one.
    case SyncActivity.pulling:
      if (syncUpdatingText(l10n, status) case final updating?) {
        return (updating, Icons.cloud_download_outlined, false);
      }
      return status.downloadedRows > 0
          ? (
              l10n.syncDownloading(status.downloadedRows),
              Icons.cloud_download_outlined,
              false,
            )
          : (l10n.syncReceiving, Icons.cloud_download_outlined, false);
    case SyncActivity.idle:
      break;
  }
  if (status.lastFailure case final failure?) {
    return failure.failure == SyncGatewayFailure.offline
        ? (
            manual ? l10n.syncOfflineManual : l10n.syncOffline,
            Icons.cloud_off_outlined,
            false,
          )
        : (
            manual ? l10n.syncFailedManual : l10n.syncRetrying,
            Icons.error_outline_rounded,
            false,
          );
  }
  if (status.pendingCount > 0) {
    return (
      l10n.syncPendingCount(status.pendingCount),
      Icons.cloud_queue_rounded,
      true,
    );
  }
  // Nothing received yet is not up to date: the details would say "Not
  // synced yet" beside it.
  if (status.lastPullAt == null) {
    return (l10n.syncWaitingFirst, Icons.cloud_queue_rounded, false);
  }
  if (manual) {
    return (l10n.syncManualIdle, Icons.cloud_outlined, false);
  }
  return (l10n.syncUpToDate, Icons.cloud_done_outlined, false);
}

/// [child] in the tile's subtitle style, for the status row's details,
/// which sit in its title slot under the line.
Widget _asSubtitle(BuildContext context, Widget child) =>
    DefaultTextStyle.merge(
      style: ListTileTheme.of(context).subtitleTextStyle,
      child: child,
    );

/// A description slot as tall as the tallest of [templates] at its width,
/// whatever [child] says: a longer text ellipsizes on the slot's last line
/// rather than growing the row. The lines are counted in the ambient style
/// the description is drawn in, under the caption role it carries.
class SyncFixedLinesSlot extends StatelessWidget {
  final List<String> templates;
  final Widget child;

  const SyncFixedLinesSlot({
    super.key,
    required this.templates,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(settingsCaptionStyle);
    return LayoutBuilder(
      builder: (context, constraints) {
        var lines = 1;
        for (final template in templates) {
          lines = math.max(
            lines,
            _linesOf(context, template, style, constraints.maxWidth),
          );
        }
        return FormCaptionSlot(
          candidates: [
            for (final template in templates)
              Text(template, style: settingsCaptionStyle),
          ],
          child: DefaultTextStyle.merge(
            maxLines: lines,
            overflow: TextOverflow.ellipsis,
            child: child,
          ),
        );
      },
    );
  }
}

/// The lines [text] takes in [style] at [width], laid out as a `Text` in
/// [context] would lay it out.
int _linesOf(BuildContext context, String text, TextStyle style, double width) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    textHeightBehavior: DefaultTextStyle.of(context).textHeightBehavior,
  )..layout(maxWidth: width);
  final lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
}

/// The status row's text: the line over the details, in a slot as tall as
/// the tallest line [templates] may say over one details line. The slot is a
/// budget of lines: a status line shorter than the tallest leaves its lines
/// to the details, which ellipsize only past what is left (review D3-1), so
/// the time is never cut while room sits under it. A screen reader hears the
/// details whole either way.
class SyncStatusLines extends StatelessWidget {
  final List<String> templates;
  final String line;
  final Widget title;
  final Widget details;

  const SyncStatusLines({
    super.key,
    required this.templates,
    required this.line,
    required this.title,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        var budget = 1;
        for (final template in templates) {
          budget = math.max(budget, _linesOf(context, template, style, width));
        }
        // One line more than the tallest status line: the details' own.
        final detailLines = math.max(
          1,
          budget + 1 - _linesOf(context, line, style, width),
        );
        return FormCaptionSlot(
          candidates: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FormCaptionSlot(
                  candidates: [
                    for (final template in templates) Text(template),
                  ],
                  child: const SizedBox.shrink(),
                ),
                // The details' own line: any one line of the details style
                // sizes it, so a fixed text never re-lays out the slot.
                _asSubtitle(
                  context,
                  Text(
                    AppLocalizations.of(context)!.syncNeverSynced,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              title,
              _asSubtitle(
                context,
                DefaultTextStyle.merge(
                  maxLines: detailLines,
                  overflow: TextOverflow.ellipsis,
                  child: details,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The spinner a Sync section row shows in its glyph's place while its step
/// runs. Silent: the row says it is working, after its name (review RC2-5).
class SyncRowBusyIndicator extends StatelessWidget {
  const SyncRowBusyIndicator({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: SizedBox.square(
      dimension: FormMetrics.rowBusyIndicatorSize,
      child: CircularProgressIndicator(
        strokeWidth: FormMetrics.rowBusyIndicatorStroke,
      ),
    ),
  );
}

/// A Sync section row's value while its step runs: a screen reader hears
/// the row's name, then that it is working, rather than its idle words
/// alone (final review D-2). A value, not a label on the spinner, which
/// would be read before the name (review RC2-5).
class SyncBusyValue extends StatelessWidget {
  final bool busy;
  final Widget child;

  const SyncBusyValue({super.key, required this.busy, required this.child});

  @override
  Widget build(BuildContext context) => Semantics(
    value: busy ? AppLocalizations.of(context)!.syncBusyLabel : null,
    child: child,
  );
}
