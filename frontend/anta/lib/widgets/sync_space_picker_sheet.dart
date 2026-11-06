import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../bloc/sync/sync_bloc.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../services/sync/sync_gateway.dart';
import 'form_rows.dart';

/// A sync time as the Sync section and the picker say it: the time of day
/// when it is today — a sync minutes ago is what the owner checks — else
/// the date, with the year only when it is not this one.
String formatSyncMoment(BuildContext context, DateTime at, {DateTime? now}) {
  final local = at.toLocal();
  final today = now ?? DateTime.now();
  if (DateUtils.isSameDay(local, today)) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }
  final localeName = AppLocalizations.of(context)!.localeName;
  return local.year == today.year
      ? DateFormat.MMMd(localeName).format(local)
      : DateFormat.yMMMd(localeName).format(local);
}

/// The bind picker (D2 A of `docs/cloud-sync-phase-02-own-space.md`): which
/// of the account's spaces this database syncs with, and how. Opened once
/// per [SyncBindPicking]; answers the event the choice stands for, or null
/// when it is closed without one.
///
/// A database that holds data picks a space and then merges into it,
/// downloads it into a new database or uploads itself as a new space; one
/// that holds nothing has nothing to merge, so each space is an action row
/// that syncs with it. With one space there is no list — the choices name
/// it; under a list they say "the selected space", so a pick changes the
/// check mark and nothing else, and the sheet never resizes under the
/// finger.
///
/// A form sheet with no draft: nothing is lost by leaving, so every way out
/// leaves at once, and a choice closes the sheet the moment it is made —
/// the Sync section shows the step running.
class SyncSpacePickerSheet extends StatefulWidget {
  final SyncBindPicking picking;

  const SyncSpacePickerSheet({super.key, required this.picking});

  static Future<SyncEvent?> show(
    BuildContext context, {
    required SyncBindPicking picking,
  }) {
    return showModalBottomSheet<SyncEvent>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      // The frame owns the drag and paints the ground and the radius.
      enableDrag: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height * FormMetrics.sheetHeightFactor,
        ),
        child: SyncSpacePickerSheet(picking: picking),
      ),
    );
  }

  @override
  State<SyncSpacePickerSheet> createState() => _SyncSpacePickerSheetState();
}

class _SyncSpacePickerSheetState extends State<SyncSpacePickerSheet> {
  final FormHeaderHairline _hairline = FormHeaderHairline();

  /// The space the choices name: the one space, or the one picked in the
  /// list — at first the most recently used that no other database holds,
  /// none when every listed space is held, so no row shows a selection it
  /// cannot have.
  late SyncSpaceInfo? _target = _firstFree();

  SyncBindPicking get _picking => widget.picking;

  bool get _listed => _picking.spaces.length > 1;

  @override
  void dispose() {
    _hairline.dispose();
    super.dispose();
  }

  SyncSpaceInfo? _firstFree() {
    final spaces = _picking.spaces;
    for (final space in spaces) {
      if (!_picking.heldBy.containsKey(space.ref)) return space;
    }
    // One held space is still what its choices name: they stay, disabled,
    // saying which database holds it.
    return _listed || spaces.isEmpty ? null : spaces.first;
  }

  void _pick(SyncEvent event) => Navigator.of(context).pop(event);

  void _close() => Navigator.of(context).pop();

  String _usedCaption(AppLocalizations l10n, SyncSpaceInfo space) {
    final at = space.lastWriteAt;
    return at == null
        ? l10n.syncPickerNotUsed
        : l10n.syncPickerLastUsed(formatSyncMoment(context, at));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    return FormSheetFrame(
      mainAxisSize: MainAxisSize.min,
      onLeave: () async => _close(),
      isClean: () => true,
      onDismiss: _close,
      chrome: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormSheetHandle(),
          FormSheetHeader(
            leadingIcon: Icons.close_rounded,
            leadingTooltip: l10n.cancel,
            leadingIdentifier: SemanticsIds.syncPickerClose,
            onLeading: _close,
            title: l10n.syncPickerTitle,
            scrolled: _hairline.scrolled,
            trailing: const SizedBox.shrink(),
            trailingInset: FormMetrics.headerActionInset,
          ),
        ],
      ),
      body: [
        Flexible(
          child: _hairline.watch(
            child: Semantics(
              identifier: SemanticsIds.syncPicker,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  RowMetrics.groupInset,
                  FormMetrics.bodyTop,
                  RowMetrics.groupInset,
                  FormMetrics.bodyBottom + clearance,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_listed) ...[
                      FormSectionLabel(text: l10n.syncPickerSpaces),
                      FormRowGroup(
                        children: [
                          for (final space in _picking.spaces)
                            _picking.holdsData
                                ? _spaceRow(l10n, space)
                                : _joinRow(l10n, space),
                        ],
                      ),
                    ],
                    FormRowGroup(
                      trailingGap: false,
                      children: [
                        ..._targetRows(l10n),
                        FormPickerRow(
                          glyph: Icons.cloud_upload_outlined,
                          label: l10n.syncPickerUpload,
                          showChevron: false,
                          identifier: SemanticsIds.syncPickerUpload,
                          onTap: () => _pick(const UploadAsNewSpaceRequested()),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// A space of the list a database that holds data picks from: the space
  /// its choices act on. A space another database of this install holds
  /// stays listed, disabled, saying which database that is — the one place
  /// the reason is said.
  Widget _spaceRow(AppLocalizations l10n, SyncSpaceInfo space) {
    final holder = _picking.heldBy[space.ref];
    return FormCheckRow(
      label: space.name,
      caption: holder == null
          ? _usedCaption(l10n, space)
          : l10n.syncPickerHeldBy(holder),
      checked: space == _target,
      exclusive: true,
      identifier: SemanticsIds.syncPickerSpace(space.ref.spaceId),
      onChanged: holder != null ? null : (_) => setState(() => _target = space),
    );
  }

  /// A space of the list a database that holds nothing syncs with at once:
  /// with nothing to merge there is nothing to select first, so the row is
  /// the action, drawn as the one-space "Sync with" row is.
  Widget _joinRow(AppLocalizations l10n, SyncSpaceInfo space) {
    final holder = _picking.heldBy[space.ref];
    return FormPickerRow(
      glyph: Icons.sync_rounded,
      label: l10n.syncPickerJoin(space.name),
      caption: holder == null
          ? _usedCaption(l10n, space)
          : l10n.syncPickerHeldBy(holder),
      showChevron: false,
      enabled: holder == null,
      identifier: SemanticsIds.syncPickerSpace(space.ref.spaceId),
      onTap: () => _pick(MergeIntoSpaceRequested(space)),
    );
  }

  /// The choices that act on [_target]: merge and download for a database
  /// that holds data, "Sync with" for an empty one with no list to pick
  /// from. Under a list they name "the selected space"; alone they name the
  /// one space and, while another database holds it, stay disabled with the
  /// holder said once, on the first of them.
  List<Widget> _targetRows(AppLocalizations l10n) {
    final target = _target;
    if (_listed) {
      if (!_picking.holdsData) return const [];
      return [
        FormPickerRow(
          glyph: Icons.merge_rounded,
          label: l10n.syncPickerMergeSelected,
          showChevron: false,
          enabled: target != null,
          identifier: SemanticsIds.syncPickerMerge,
          onTap: target == null
              ? null
              : () => _pick(MergeIntoSpaceRequested(target)),
        ),
        FormPickerRow(
          glyph: Icons.download_rounded,
          label: l10n.syncPickerDownloadSelected,
          showChevron: false,
          enabled: target != null,
          identifier: SemanticsIds.syncPickerDownload,
          onTap: target == null
              ? null
              : () => _pick(DownloadSpaceRequested(target)),
        ),
      ];
    }
    if (target == null) return const [];
    final holder = _picking.heldBy[target.ref];
    final heldBy = holder == null ? null : l10n.syncPickerHeldBy(holder);
    if (!_picking.holdsData) {
      return [
        FormPickerRow(
          glyph: Icons.sync_rounded,
          label: l10n.syncPickerJoin(target.name),
          caption: heldBy ?? _usedCaption(l10n, target),
          showChevron: false,
          enabled: holder == null,
          identifier: SemanticsIds.syncPickerMerge,
          onTap: () => _pick(MergeIntoSpaceRequested(target)),
        ),
      ];
    }
    return [
      FormPickerRow(
        glyph: Icons.merge_rounded,
        label: l10n.syncPickerMerge(target.name),
        caption: heldBy,
        showChevron: false,
        enabled: holder == null,
        identifier: SemanticsIds.syncPickerMerge,
        onTap: () => _pick(MergeIntoSpaceRequested(target)),
      ),
      FormPickerRow(
        glyph: Icons.download_rounded,
        label: l10n.syncPickerDownload(target.name),
        showChevron: false,
        enabled: holder == null,
        identifier: SemanticsIds.syncPickerDownload,
        onTap: () => _pick(DownloadSpaceRequested(target)),
      ),
    ];
  }
}
