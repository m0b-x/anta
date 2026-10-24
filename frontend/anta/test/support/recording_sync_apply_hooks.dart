import 'package:anta/services/sync/sync_apply_hooks.dart';
import 'package:anta/services/sync/sync_table_binding.dart';

/// Records every [SyncApplyHooks] call the engine makes, in order, so a test
/// can assert when the app would have been told what — the production hooks
/// (S3c) act on exactly these calls.
class RecordingSyncApplyHooks implements SyncApplyHooks {
  /// Every call as `before:<table>`, `after:<table>`, `run` or `conflict`.
  final List<String> calls = [];

  /// Each `afterPage`, with the rows it carried.
  final List<(String, List<SyncAppliedRow>)> pages = [];

  /// Each `afterRun`'s touched classes.
  final List<Set<SyncInvalidation>> runs = [];

  final List<SyncNoteConflict> conflicts = [];

  /// Runs inside `beforePage`, so a test can act mid-run — begin a
  /// suspension while a page is about to be merged.
  Future<void> Function(String table)? onBeforePage;

  /// Runs inside `afterPage` after the call is recorded, so a test can hand
  /// the page to the production hooks.
  Future<void> Function(String table, List<SyncAppliedRow> rows)? onAfterPage;

  /// Runs inside `afterRun` after the call is recorded, so a test can make
  /// the hook throw.
  Future<void> Function()? onAfterRun;

  /// Runs inside `fileConflictCopy` before the conflict is recorded — inside
  /// the page's transaction — so a test can file a copy (returning its id),
  /// look at the page's state from within, or throw to roll the page back.
  Future<String?> Function(SyncNoteConflict conflict)? onConflict;

  void clear() {
    calls.clear();
    pages.clear();
    runs.clear();
    conflicts.clear();
  }

  @override
  Future<void> beforePage(String table) async {
    calls.add('before:$table');
    await onBeforePage?.call(table);
  }

  @override
  Future<void> afterPage(String table, List<SyncAppliedRow> rows) async {
    calls.add('after:$table');
    pages.add((table, rows));
    await onAfterPage?.call(table, rows);
  }

  @override
  Future<void> afterRun(Set<SyncInvalidation> touched) async {
    calls.add('run');
    runs.add(touched);
    await onAfterRun?.call();
  }

  @override
  Future<String?> fileConflictCopy(SyncNoteConflict conflict) async {
    calls.add('conflict');
    final copy = await onConflict?.call(conflict);
    conflicts.add(conflict);
    return copy;
  }
}
