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

/// How long after a shared read a pass still counts as the one that read
/// asked for, and may plan the check from now (`SharedRefresh.readMade`).
/// The pass a read asks for follows it within its reloads — seconds, and
/// never more than a run's limit; a read that changed nothing asks for
/// none, and must not stand for whichever pass comes next. Two minutes is
/// twice that limit, and well under the shortest gap a plan can have
/// ([kSharedRefreshMinGap]): no read this old can be the reason a check
/// that has fallen due is moved.
const Duration kSharedRefreshReadPassWindow = Duration(minutes: 2);

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

/// How many pings go unanswered before a name is called a dead isolate's —
/// six seconds in all: one alone was a main isolate stalled by a restore or
/// a long frame, and the run that followed wrote beside a live app.
const int kSharedRefreshPings = 3;

/// How often the app takes its name again while it is in front: what a
/// trigger removed in spite of the pings is back within this, and the run
/// that went on without the app is asked to end.
const Duration kSharedRefreshReassertEvery = Duration(seconds: 10);

/// How long a launch waits for a run in flight to close the database before
/// it goes on and opens it.
const Duration kSharedRefreshYieldTimeout = Duration(seconds: 5);

/// How many ends in a row may still owe what a work was started for before
/// the row is ended. For a message's work every end that owes its read
/// counts, and each hands a fresh work to the platform (`fireSharedRefresh`)
/// — the platform itself is not asked: unbounded, a cause that never heals
/// would hand works over without end. For the check's own work its
/// give-ways to another run count, each run again by the platform, whose
/// back-off has no end of its own and whose attempt count never reaches
/// Dart.
const int kSharedRefreshGiveWayAttempts = 3;

/// The longest a trigger works, read and alert pass together: past it the
/// run ends where it is and the platform is asked to try again. Well under
/// the ten minutes Android grants a work, and what a message's wake-up can
/// count on.
const Duration kSharedRefreshRunLimit = Duration(seconds: 60);

/// What a step in flight is given to end once the limit or the platform
/// cut the run: a read stops before its next page, not inside one. Past it
/// the trigger leaves the step where it is — one that never returned held
/// the run's name for good, and every later trigger ended busy.
const Duration kSharedRefreshAbandonGrace = Duration(seconds: 5);

/// How long a trigger that left a step behind waits for the database to
/// close before it gives its name up regardless: the close may be waiting
/// on the very thing that hung.
const Duration kSharedRefreshAbandonCloseBound = Duration(seconds: 2);

/// How long the app waits on a read a trigger forwarded before it stops
/// counting the asker as waiting — five seconds under the asker's own
/// limit ([kSharedRefreshRunLimit]). Equal, the two ran out in one turn of
/// the clock, and a read begun in it ran for an asker that had just been
/// answered failure.
const Duration kSharedRefreshForwardPatience = Duration(seconds: 55);

/// How long a launch gives the holder of the run's name to answer a ping
/// or give way before it calls the name a dead run's and removes it. A
/// live run answers a ping within a turn of its isolate; a name left by a
/// run killed with its engine cost every launch the whole
/// [kSharedRefreshYieldTimeout], and was still there for the next.
const Duration kSharedRefreshDeadRunAfter = Duration(seconds: 1);

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

/// How long the note that a pair's message work waits to start is believed
/// (`SharedRefreshMessageGate`): past it the next message schedules a work
/// again. The platform cannot be asked instead — the plugin's own question
/// answers "no" for a unique name whose chain holds a finished or a blocked
/// work, which an appended chain always does. Ten minutes covers a run's
/// limit ahead of the work and the platform's first back-offs; a work that
/// was lost swallows its pair's messages for no longer.
const Duration kSharedRefreshWaitingMarkAge = Duration(minutes: 10);

/// How many of each kind of notice a database keeps for the next open —
/// events that arrived, categories that arrived, events that left with an
/// alert. Past it the oldest go: the bar counts a handful, never a list.
const int kShareNoticesKeptMax = 20;
