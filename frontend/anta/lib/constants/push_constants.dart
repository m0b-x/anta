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

/// The longest pause a relay's `Retry-After` (429, 503) is honoured for:
/// the relay's own budget is an hour's, and a longer or garbled value must
/// not silence this phone's pokes for the rest of the process. Pokes asked
/// for inside the pause are dropped — the partner's phone has its own check.
const Duration kPushRetryAfterCeiling = Duration(hours: 1);

/// How long a pair the relay refused (403) is not poked again as the
/// account that asked. The relay's own refusal — not a member, the pair
/// gone — does not change within the hour; an edge in front of it can
/// answer a 403 for a cause that passes, and must not silence the pair
/// until the app is killed.
const Duration kPushRefusalHolds = Duration(hours: 1);

/// How long a registration waits for the platform to name its address.
const Duration kPushRegisterDeadline = Duration(seconds: 30);

/// How long each call that ends an address — the unregister, the
/// installation's delete — may take before it is left behind: a platform
/// that never answers holds no later step of the registry, and a delete not
/// confirmed stays owed.
const Duration kPushEndDeadline = Duration(seconds: 30);

/// How long the removal of this device's entry may hold a sign-out.
const Duration kPushLeaveDeadline = Duration(seconds: 5);

/// How long an engine with no app waits for the alarm host to hear that it
/// is no presenter, before it goes on regardless: the messaging plugin's
/// background handler, ahead of handing a message's work over
/// (`handleBackgroundPush`), and the check's own work at its entry, ahead
/// of its trigger (`sharedRefreshTask`). The call is one to a host in the
/// same process and answers in milliseconds; two seconds is a host that is
/// not answering, and a small part of the time the platform gives either.
const Duration kPushResignBound = Duration(seconds: 2);

/// The first Android API level (12) whose system runs an expedited work
/// without a foreground notification: below it WorkManager asks the worker
/// for one, which the plugin's worker cannot give, and a notification about
/// sharing is what D23 rules out.
const int kExpeditedWorkMinSdk = 31;

/// The relay's own rule for a pair id (`backend/push-relay`): a message
/// naming anything else did not come from a poke, and costs nothing.
const String kPushPairPattern = r'^[A-Za-z0-9_-]{1,128}$';

/// How long the app in front gathers relay messages before the one shared
/// read they ask for: a partner's burst of edits is one read.
const Duration kPushMessageCoalesce = Duration(seconds: 2);

/// With the app in front, at most one shared read a message asks for in
/// this long: the first after a quiet floor reads once its gather ends, any
/// within it lead to one read at the floor's end. An honest partner's
/// messages already come at most once a minute per pair
/// ([kPushPokeSpacing]); this bounds what does not.
///
/// For the app in front alone, where waiting out the floor costs seconds.
/// Not in front there is no floor: a work put off to its end is a plain
/// one, which a phone asleep holds with every later message's work queued
/// behind it — and the honest second message, sent a spacing after the
/// first, starts inside it.
const Duration kPushReadFloor = Duration(minutes: 1);
