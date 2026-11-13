// How this phone keeps its push address in the pair's document and pokes
// the relay (`docs/cloud-shared-freshness.md` §7).

/// An entry is written again once it is this old, address unchanged: the
/// relay skips one older than [kPushDeviceStale], so a phone that stays
/// paired never ages out.
const Duration kPushDeviceRefresh = Duration(days: 7);

/// A device of mine that has not written its entry for this long is gone —
/// the relay no longer sends to it, and my next device that writes drops it.
const Duration kPushDeviceStale = Duration(days: 60);

/// How often a paired phone reads where the relay is (`config/push`).
const Duration kPushRelayReadInterval = Duration(days: 1);

/// After a read of `config/push` that failed, how long before the next one
/// is tried: the last value stands meanwhile.
const Duration kPushRelayRetryAfterFailure = Duration(hours: 1);

/// The first poke after a quiet window goes at once; those asked for within
/// it are sent at its end, one per pair. A minute keeps a busy evening under
/// the relay's sixty an hour per caller.
const Duration kPushPokeSpacing = Duration(minutes: 1);

/// The whole poke — the token, the connection and the answer — or it is
/// dropped.
const Duration kPushPokeDeadline = Duration(seconds: 10);

/// How long a registration waits for the platform to name its address.
const Duration kPushRegisterDeadline = Duration(seconds: 30);

/// How long the removal of this device's entry may hold a sign-out.
const Duration kPushLeaveDeadline = Duration(seconds: 5);

/// The first Android API level (12) whose system runs an expedited work
/// without a foreground notification: below it WorkManager asks the worker
/// for one, which the plugin's worker cannot give, and a notification about
/// sharing is what D23 rules out.
const int kExpeditedWorkMinSdk = 31;

/// How long the app in front gathers relay messages before the one shared
/// read they ask for: a partner's burst of edits is one read.
const Duration kPushMessageCoalesce = Duration(seconds: 2);
