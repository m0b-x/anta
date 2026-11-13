import 'package:workmanager/workmanager.dart';

import '../../constants/shared_refresh_constants.dart';
import 'shared_refresh_app.dart';
import 'shared_refresh_scheduler.dart';
import 'shared_refresh_trigger.dart';

/// Where the platform starts Dart for the check, in an engine of its own
/// with no app behind it (`docs/cloud-shared-freshness.md` §6).
///
/// The platform finds it by a handle stored when the app last scheduled
/// the work, so it stays a top-level function in this library under this
/// name: moved or renamed, a work scheduled by the build before would find
/// nothing to run.
///
/// False asks the platform to run the work again on its back-off; a stop
/// from the platform — its time is up, the network left — ends the run
/// where it is before the isolate is torn down.
@pragma('vm:entry-point')
void sharedRefreshEntry() {
  Workmanager().executeTask(
    (task, inputData) => fireSharedRefresh(
      cause: SharedRefreshCause.fromInput(inputData),
      // The check's task is named for the slot it was scheduled in.
      slot: SharedRefreshSlot.ofTask(task),
      pair: switch (inputData?[kSharedRefreshPairKey]) {
        final String pair => pair,
        _ => null,
      },
    ),
    onTaskStopped: (task, reason) => stopSharedRefresh(),
  );
}
