// The check's timing and its name on the platform: when the phone reads
// what the partner shares by itself (`docs/cloud-shared-freshness.md` §4,
// decision c).

/// No check comes sooner than this, and an alert nearer than this takes no
/// further one: a run needs the network and the system's own window, so a
/// check planned minutes before a ring would mostly land after it.
const Duration kSharedRefreshMinGap = Duration(minutes: 10);

/// No check waits longer than this, however far the nearest alert is: a
/// share that ended or an event moved a week early is then never more than
/// half a day stale.
const Duration kSharedRefreshMaxGap = Duration(hours: 12);

/// The ceiling under "Category alerts too", and the gap when no alert is
/// armed there yet: an event the partner adds to a category that rings here
/// has to be read before it can arm at all.
const Duration kSharedRefreshCategoryMaxGap = Duration(hours: 1);

/// How far apart two planned instants may be and still be one plan — what
/// lets a second alert pass moments after the first ask the platform
/// nothing.
const Duration kSharedRefreshSameInstant = Duration(minutes: 1);

/// The unique name the check's work has when the app schedules it, and the
/// task name its run is handed. Stored by the platform across restarts and
/// updates: never rename it, or a build would leave the old name's work
/// standing beside its own.
const String kSharedRefreshWorkName = 'shared-refresh';

/// The second name the work may live under (`SharedRefreshSlot`): where a
/// run that is itself the first schedules its successor. Stored by the
/// platform like the first.
const String kSharedRefreshSecondWorkName = 'shared-refresh-2';

/// The name the app's isolate answers under in the process's port registry
/// (`docs/cloud-shared-freshness.md` §5). Process-local, so it may change
/// between builds.
const String kSharedRefreshAppPort = 'anta.app';

/// The name a run without the app holds for as long as it may hold the
/// database.
const String kSharedRefreshRunPort = 'anta.refresh';

/// How long a trigger waits for the app's isolate to answer a ping before
/// it takes the name for a dead isolate's and removes it.
const Duration kSharedRefreshPingTimeout = Duration(seconds: 2);

/// How long a launch waits for a run in flight to close the database before
/// it goes on and opens it.
const Duration kSharedRefreshYieldTimeout = Duration(seconds: 5);

/// The longest a trigger works, read and alert pass together: past it the
/// run ends where it is and the platform is asked to try again. Well under
/// the ten minutes Android grants a work, and what a message's wake-up can
/// count on.
const Duration kSharedRefreshRunLimit = Duration(seconds: 60);

/// How long a run waits to learn who is signed in: the identity restores
/// the stored account as the isolate starts, and an account that is merely
/// not restored yet must not read as nobody.
const Duration kSharedRefreshAccountWait = Duration(seconds: 5);

/// How often a launch that waits for a run looks whether the run's name is
/// still there.
const Duration kSharedRefreshYieldPoll = Duration(milliseconds: 250);

/// The key of a work's input data that names what started it
/// (`SharedRefreshCause`). Stored by the platform with the work: never
/// rename it.
const String kSharedRefreshCauseKey = 'cause';

/// The unique work a relay message starts — apart from the schedule's own
/// names, so a message never moves or cancels the planned check. Stored by
/// the platform: never rename it.
const String kSharedRefreshMessageWorkName = 'shared-refresh-message';

/// The key of a message work's input data that names the pair the message
/// was for: a run for another database's pair reads nothing (case B13).
/// Stored by the platform with the work: never rename it.
const String kSharedRefreshPairKey = 'pair';

/// How many of each kind of notice a database keeps for the next open —
/// events that arrived, categories that arrived, events that left with an
/// alert. Past it the oldest go: the bar counts a handful, never a list.
const int kShareNoticesKeptMax = 20;
