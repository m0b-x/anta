# Shared Freshness — ANTA

**Status: BUILT AND PAUSED 2026-11-13, not committed, nothing deployed —
slice I (the check) and slice J (the relay) of
`cloud-share-surfaces-roadmap.md` §16. §12 says what is built and is the
truth over the plan above it; its last block, "Open at the pause", says
what the review of the check still asks for.** This is the design
record for one promise: an alert of mine on something my partner shares
follows their changes while ANTA is closed. It replaces the push section
of `cloud-sync-connections-design.md` (2026-08, three pairing moments and
tokens under the account) and is the roadmap's P6
(`cloud-multi-user-roadmap.md` §10). Android only (§10).

Written by the session's lead, Fable 5.2, on the owner's word of
2026-11-13 ("Fix the third" — of "An alert on a shared event follows what
the phone last synced; there is no push"). No agent took a decision in it.

## Contents

1. Why
2. Decisions
3. The model
4. The check — when the phone looks by itself
5. One isolate holds the database
6. The run without the app
7. The relay — the wire
8. The relay — the Worker
9. The owner's steps
10. Cases
11. Must not change; deferred
12. As built

---

## 1. Why

The reader of a partner's rows runs while the app is in use: at start, on
"Sync now", every five minutes while open (`SyncEngine.sharedReadInterval`).
Alerts are the one thing that acts while the app is closed, and they were
armed from what the phone last read: {name} moves the night shift to 23:00,
my phone rings at 21:30; {name} cancels it, my phone rings anyway (the
share record's A7). The cure has two halves that need each other:

- the phone has to be able to **do the read with the app closed** — a run
  of Dart with the database and the network, which the app has never had
  (`android_alert_gateway.dart:245`: its one background isolate "shares
  nothing with the app: no database");
- something has to **tell it when** — its own schedule, which needs no
  server and can be proven here, and a message from the other phone, which
  needs a sender outside the app because a client cannot hold the
  credential that sends one.

## 2. Decisions

Taken by the lead on the owner's delegation; the option not taken is named.

| # | Decision | Why, and the option not taken |
| --- | --- | --- |
| a | **Two triggers, one job.** The job reads what the partner shares and reconciles the alerts — nothing else, never a push or a pull of my own space. It is started by the phone's own schedule (the check, §4) and by a message from the relay (§7). | One piece of code to prove. Not taken: a background sync of everything — my own rows need no freshness while the app is closed, and a pull can be long. |
| b | **Only while an alert depends on it.** Nothing is scheduled and a message does nothing unless this database syncs, is paired, and something of the partner's can ring here: an alert of mine is armed on one of their events, or "Category alerts too" is on and a category they share has alerts of mine. | Alerts are what must not be stale; the calendar itself is read when it is opened. The default — "Only alerts I add", none added — costs no wake-up at all. Not taken: refreshing for everyone who is paired. |
| c | **The check comes sooner as an alert comes near**: the next one is at half the time left to the nearest armed alert on a partner's event, no sooner than ten minutes from now, no later than twelve hours (one hour under "Category alerts too", where a new event may need arming). | A fixed quarter-hour would wake the phone a hundred times a day for a daily alert; halving does it seven times and still looks within twenty minutes of the ring. Not taken: an exact alarm minutes before each alert — a second mechanism for the one gap the relay closes. |
| d | **One isolate holds the database.** A background trigger first asks the app's own isolate to do the read; only when no app is running does it open the database itself, and a launch that finds such a run in flight waits for it to yield (§5). | The app's caches, its Drift streams and its settings live in one isolate; a second writer would leave them stale. This keeps the rule the alert gateway wrote down, and gives it its one exception with a protocol. |
| e | **A run without the app never migrates and never creates**: a database file whose schema is not this build's is left alone until the app is opened. | A migration belongs under "Finishing the update", in front of the person. |
| f | **What a run found is said later**: an arrival or a leave that took an alert of mine is kept with the database and said at the next open (the share record's D23, D30). Never a system notification. | D23 stands. Not taken: a notification "{name} moved Night shift" — the owner has not asked for one. |
| g | **The relay is a Cloudflare Worker in this repository** (`backend/push-relay/`), deployed by the owner; the app works without it, exactly as slice I leaves it. | The connections design's answer to "no server functions on the free plan", unchanged. Not taken: the paid plan's functions (a card); FCM topics (no sender needed for subscribing, but one is still needed for sending, and topic delivery is built for throughput, not for two phones). |
| h | **A device's push address lives in the pair's document** — `push.<uid>.<deviceId> = {id, kind, at}` — written by its owner, read by both members. The relay reads it **with the caller's own sign-in**, so the rules decide who may wake whom, and the relay's own credential can only send messages. | The connections design kept tokens under the account and gave the relay a credential that could read them — which is a credential that can read every account. Not taken: that; a subcollection under the pair (it would outlive a deleted pair — there is no recursive delete). |
| m | **The address is a Firebase Installation ID** (`kind: fid`), not a registration token: Google's reference marks the token deprecated ("Use `fid` instead", read 2026-11-13), and the Flutter API for it arrives with `firebase_messaging` 17, which takes `firebase_core`, `firebase_auth` and `cloud_firestore` up one major (slice J0). The entry names its kind, so the relay serves both. | New code is not born on an API its maker is retiring. Not taken, unless J0 shows the upgrade cannot be done safely: `firebase_messaging` 16 with `getToken()` — the fallback, one adapter class away (`kind: token`). |
| n | **An address dies with its pair.** When a pair ends — by either person — and at sign-out, the phone gives up its installation id, and makes a new one when it next registers. | The relay's review (F2): a former partner knows the address and could write it under a pair of their own making to keep waking the phone. Nothing binds an address to an account on the server; rotating it makes the old one worthless. Not taken: a registry of who owns which address, read by the relay at every poke. |
| i | **A message carries nothing**: `{t: shared, p: <pair id>}`. It is a poke; the phone reads the truth from the cloud. | Nothing private leaves through a third party, and a lost or repeated message changes nothing. |
| j | **Urgent only when it can ring.** A change to the calendar's shared rows — a share of one that began or ended included — and a pair that ended: high priority. Everything about a note or a folder, a share of one that ended too: normal priority — it is read when the partner next looks, and a phone that is awake gets a normal message at once anyway. | Android demotes an app whose high-priority messages show nothing to the person. |
| k | **Where the relay is** is one document, `config/push {relay: <url>}`, written in the console, read at most once a day by a paired phone. No document, no relay: nothing registers and nothing is sent. | The build and the deploy stay independent. Not taken: a build-time constant — a rebuild of both phones for a URL. |
| l | **No switch.** | The work happens only for an alert the person added or a setting they chose; Android's own per-app battery control stays the override. |
| o | **A message's work is expedited where that shows nothing** — Android 12 and later. There an expedited work may run, and use the network, while the phone sleeps deeply; a plain one runs only inside the few seconds a high-priority message grants and is stopped when they end. On Android 11 and older the same request needs a foreground notification, so the work stays plain there and the read lands inside the message's own seconds, or at the system's next window. The handler's isolate cannot ask which Android it is on; the app's isolate notes the answer whenever it hands the handler over. The check's own work is never expedited: it is planned, not urgent. | Case B8 as the receiving side was first built: the message arrived and its work waited (read from WorkManager 2.11.2: `workForeground` asks for no foreground info from API 31; the job is marked expedited only there). Not taken: expedited everywhere — a notification for a background read (D23); the read inside the messaging plugin's own isolate — a third holder of the database (decision d); a device-information dependency for one number. |

## 3. The model

```
{name}'s phone                    cloud                         my phone
--------------                    -----                         --------
edits a shared event
push run sends the row  ───────►  Firestore
poke(pair, urgent)      ───────►  relay ── FCM data ────────►   in front: readSharedNow()
                                                                closed:   the job, now
                                                    the check ─►          the job, at its time
                                                                the job = shared read + alert pass
                                                                          └ armed alerts follow
```

Three new pieces in the app, each behind an interface with a fake:

- `SharedRefresh` (`lib/services/shared_refresh/`): the planner (pure),
  the scheduler of the job (a gateway over `workmanager`), the job's entry
  point, the handshake of §5.
- `PushRegistry`: this device's address in the pair's document.
- `PushRelay`: the poke after a push run, and where the relay is.

## 4. The check — when the phone looks by itself

**Wanted** (decision b) is decided where the alert pass ends, from what it
just armed: `AlertScheduler` already walks every event; it reports the
fire times of the registrations whose event is the partner's, whether an
alert of mine is defined on a partner's event that is not armed yet — it
lies beyond the thirty-day horizon, and the partner may move it nearer —
and whether a category the partner shares holds alerts of mine under
"Category alerts too". No second pass over the events.

**The planner** — `SharedRefreshPlan.next(now, fireTimes, categoryAlerts:)`,
pure:

- not wanted → none: the unique work is cancelled;
- `gap = (nearest future fire time − now) / 2`, held to
  `[10 min, 12 h]`; with `categoryAlerts` the ceiling is `1 h`, and with no
  fire time at all the gap is that ceiling;
- an alert at most ten minutes away takes no further check; the next
  nearest decides.

From three days ahead the checks land 60, 48, 36, 24, 12, 6 and 3 hours,
then 90, 45, 22½, 11¼ and 1¼ minutes before the ring.

**The job** is one unique one-off work (`shared-refresh`, replace), network
required, delayed by the gap. Every run schedules its successor **before**
it reads, so a run that is killed has already planned the next. The alert
pass in the app re-plans too — after an alert is added, removed, fired, or
the setting changes — so the schedule never lags the person's own acts.
A reboot keeps it (WorkManager persists its work).

**Costs.** A run that finds nothing new: the pair, and a page and a count
per shareable table — about a dozen document reads (`SyncEngine`'s own
figure). A daily alert: eight runs a day. No alert on anything shared:
none — in Dart. Below it the `workmanager` plugin initialises Android's
WorkManager when the process starts, on every install, paired or not, and
its manifest adds the short-service foreground permission that work asked
to run at once needs.

## 5. One isolate holds the database

Two names in the process's port registry (`IsolateNameServer`):

- `anta.app` — registered by the app's isolate once its database is open,
  removed when the app's engine is torn down;
- `anta.refresh` — registered by a run without the app for as long as it
  holds the database.

**A trigger** (the job, or a message that arrived in the background) looks
up `anta.app` and pings it. A pong within two seconds: the app's isolate
does the read through its own engine (`readSharedNow`, allowed while not
in front for this one caller) and answers when it has ended; the trigger's
isolate never opens the database. No pong: the name is stale — removed —
and the run goes on without the app (§6).

**A launch** looks up `anta.refresh` before it opens the database — one
synchronous lookup, no await when the name is absent, which is every
ordinary launch. Present: it sends "yield" and waits for "done" or for
five seconds; the run stops after the transaction in flight, closes the
database and answers. The app then opens it and loads fresh: nothing a
run wrote can be older than what the app holds.

A process that dies takes both names with it.

## 6. The run without the app

`sharedRefreshEntry` (`@pragma('vm:entry-point')`), in this order:

1. Firebase, through the **same** initialisation the app's `main` uses —
   the QA build's emulator routing included, so a QA run never reaches the
   live project.
2. The active database's file: absent, or its schema not this build's →
   end (decision e). Else open it — the one opening outside the app.
3. Not bound, not signed in as the bound account, not paired, or a restore
   holding `SyncSuspension` → end.
4. Schedule the successor (§4).
5. The shared read alone, through a `SyncEngine.detached` that is never
   started: no signal, no timers, no pull, no drain.
6. The reloads the read asks for and the alert pass, as
   `AppSyncApplyHooks.afterRun` does them; its notices go to the database
   (decision f, `sync_metadata`), merged with what is already kept.
7. Close the database, remove `anta.refresh`.

A hard limit of sixty seconds; past it the run ends where it is — every
page is its own transaction, so nothing is half-applied — and the work
reports "retry".

The alert pass arms through the same gateway as the app: reminders through
`flutter_local_notifications`, alarms through the owned `alarm` fork. Both
must work from an engine with no activity; the device flow proves each
tier (§12).

## 7. The relay — the wire

**The pair's document** gains one field, `push`, a map of maps:
`push.<uid>.<deviceId> = {id: string, kind: "fid" | "token", at: timestamp}`.

- Rules: an **active** pair's member may write under their own uid only;
  at most five devices per member; `id` a string of at most 4096; `kind`
  one of the two; `at` not after `request.time` (every write validates
  all of the member's entries again, so the ones already there cannot be
  asked to equal it); nothing else in the document changes in that write.
  A member may remove their own entry, of an ended pair too. Reads are
  the pair's existing rule: its members.
- `PushRegistry` writes this device's entry when the database is paired,
  syncing, a relay is known (§k) and the address differs from the stored
  one or the entry is older than seven days; removes it at sign-out and
  when sync is stopped. A device of mine that has not refreshed for sixty
  days is dropped by my next device that writes.
- **When the pair ends** — by me, or heard from the partner — and at
  sign-out, the phone removes its entry and gives up its address
  (decision n): a later registration, for a later pair, carries a new
  one.
- An older build ignores the field: `PairRecord` reads what it knows, and
  the rules' other shapes are diffs that do not name it.

**`config/push`**: `{relay: "https://…"}`. Rules: a signed-in `get`; no
list, no write. Read by a paired phone at most once a day, kept in
preferences; a failed read keeps the last value.

**The poke.** `POST <relay>/poke`, `Authorization: Bearer <Firebase ID
token>`, body `{"pair": "<id>", "urgent": true|false}`. A poke is **owed
to a pair**: the owing is written with the write that causes it — a row
sent with a grant, when its batch lands; a share act; every write that
changes a row's grant (an event's category, a move across a shared
folder's edge, a shared category deleted, a mark that arrives by a merge)
— so a run that fails after it, or an app that closes, loses none. A
drain that ends with nothing more to try for the shareable tables pays
what is owed. Ending the pair pokes directly. Urgent as decision j says.
The first poke after a quiet minute goes at once; later ones inside the
minute are merged, per pair, into one; a pending one is sent when the app
leaves the front. Never awaited by the run; a failure is logged and
forgotten — the check is the net.

**The message**: FCM v1, to `fid` (or `token`, as the entry's kind says),
`data: {t: "shared", p: <pair id>}`, `android.priority` HIGH or NORMAL,
`collapse_key` the pair's id, a time-to-live of an hour. In front: `readSharedNow()` (the engine's own
one-a-minute floor applies). Not in front: the job, now, when decision b
says it is wanted; else nothing.

## 8. The relay — the Worker

`backend/push-relay/` at the repository's root: one module, no dependency
at run time, its tests on Node's own runner with `fetch` faked.

1. `POST /poke` only (another path 404, another method 405); a body of at
   most 1 KB, read with a deadline and only after the bearer's shape was
   checked; anything else 400.
2. Verify the ID token: RS256 against Google's published keys, `aud` and
   `iss` this project, not expired, issued and signed in no later than
   now. The keys are held in the isolate's memory alone — they are what
   every decision rests on — for as long as Google says, and an unknown
   key id forces one refetch a minute at most, so nobody without an
   account can make the relay call Google per request.
3. At most six pokes a minute and sixty an hour per caller: Cloudflare's
   rate-limiting binding where it is bound, the isolate's memory
   otherwise. Past it, 429.
4. `GET pairs/<pair>` through Firestore's REST API **with the caller's
   token**. 403 or 404 → 403; any other failure → 503. The rules have then
   proven the caller is a member; `members` must be two distinct accounts,
   the caller one of them. An ended pair is served for one day — the poke
   that tells the other phone it ended — then not at all.
5. From `push`, the five newest entries of the other member no older than
   sixty days and not from the future. None → 204.
6. 204, at once. The sends follow after the answer (`waitUntil`), so
   neither its body nor its timing says whether the partner has a device.
7. An access token for FCM from the service account's key (a secret of the
   Worker; scope `firebase.messaging` only), held in memory until a minute
   before it expires, one exchange in flight, none for thirty seconds
   after a failed one.
8. One `messages:send` per entry, to `fid` or `token` as its kind says.
   Every outbound call has a five-second deadline and follows no
   redirect.

The relay keeps nothing between requests but those keys, that access
token and the counts, and logs status codes only. What it can do if it is
taken over: send content-free messages to the phones of people who used
it, and see the ID tokens of callers for as long as each lives (an hour)
— which is why its code is in the repository and its account the owner's
own. What a member can do with it: wake the other member's phone, up to
the limit above, for as long as they are paired — which sharing a calendar
already lets them do by editing it.

## 9. The owner's steps

After slice J is on both phones; none of it blocks slice I.

1. A free Cloudflare account; `npm install` and `npx wrangler deploy` in
   `backend/push-relay/`.
2. In the Google Cloud console of the project: a service account with the
   role "Firebase Cloud Messaging API Admin" and nothing else; its JSON
   key → `npx wrangler secret put FCM_SERVICE_ACCOUNT`. The project's id →
   `wrangler.toml`.
3. The rules deploy (it carries `push` and `config/push`):
   `firebase deploy --only "firestore:rules,firestore:indexes" --project alexs-note-tracking-app`.
4. In the Firebase console: the document `config/push` with one field,
   `relay`, the Worker's URL.
5. Both phones opened once while paired. Then: one changes a shared event
   with the other's app closed and an alert set on it; the alert moves.

## 10. Cases

| # | Situation | What happens |
| --- | --- | --- |
| B1 | Nothing of {name}'s can ring on my phone | No work is scheduled and a message does nothing. |
| B2 | I add an alert to their event, three days ahead | Checks every twelve hours, then at 6 h, 3 h, 90, 45, 22 and 11 minutes before it, and a last one a minute before. |
| B3 | {name} moves it while my app is closed, relay deployed | My phone is woken at once; the alert moves. |
| B4 | …no relay | It moves at the next check. A change inside the last ten minutes is not seen. |
| B5 | {name} cancels it, or stops sharing it | The alert is taken off; at my next open one notice says so. |
| B6 | {name} adds an event to a category that rings here ("Category alerts too") | Armed at the message, or at the hourly check. |
| B7 | My phone is offline | Nothing can reach it: the alert rings at the time it last knew. A queued message arrives when the phone is back, once. |
| B8 | My phone sleeps deeply (Doze) | The check waits for the system's window. An urgent message still arrives, and on Android 12 and later its read runs at once (decision o); on older Android it runs if it fits the message's own few seconds, else at the system's next window. |
| B9 | The app was force-stopped, or the maker's battery saver blocks it | Android delivers nothing and runs nothing until the app is opened — as it does for the alerts themselves. |
| B10 | I open the app while a run is in flight | The launch waits for it, at most five seconds. |
| B11 | The app is open but not in front when a trigger comes | The app's own isolate does the read. |
| B12 | The app was updated and not opened yet | The run leaves the database alone. |
| B13 | I keep several databases | Only the open one is refreshed; a message for another database's pair is ignored. |
| B14 | {name} ends the pair while my app is closed | The rows leave and their alerts with them, at the message or the next check; the notice names {name}. |
| B15 | A restore is running | The run ends at once. |
| B16 | {name} writes in a shared note | A normal-priority message: my open note redraws; a closed app does nothing. |
| B17 | iPhone, desktop | No check and no message: the caption says alerts follow what this device last received. |
| B18 | The relay is down, or not deployed | Pokes fail quietly; the check goes on. |
| B19 | A second phone of mine | It registers its own address; both are woken. |
| B20 | Someone calls the relay without being a member | 403; nothing is sent. |

## 11. Must not change; deferred

**Must not change.** An account that never paired: no new call, no new
statement, no work scheduled, no token asked for. An idle launch: one
synchronous lookup more. The sync engine's own runs, cadences and status.
"Nothing arms that the person did not ask for." The alert gateway's
background handler still touches no database. D23: no system notification
about sharing. A QA build never reaches the live project.

**Deferred.** iOS (APNs keys, background modes) with the iPhone slice
(R7). An exact check minutes before each alert (decision c's option). A
switch (decision l's option). Push for my own devices' sync — the space's
signal serves an open app, and a closed one needs nothing.

## 12. As built

One subsection per slice, appended as each lands.

### Slice I — the check (2026-11-13)

Built by one Fable implementer in three legs. Where it differs from §4–§6
above, this is the truth.

**The plan and the need.** `SharedRefreshPlan.next(now, fireTimes,
{categoryAlerts, alertDefined})`, pure; `SharedRefreshNeed` is reported
by the alert pass from the loop it already runs — no second walk, no
statement for a database whose cache holds none of the partner's events
and whose setting is not "Category alerts too" (under that setting one
read says which built-ins the partner shares). `SharedRefresh` decides
"wanted" (`need.depends` and the database bound and paired) and
schedules or cancels one unique one-off work, `shared-refresh`, network
required, replace — skipping a plan within a minute of the last one.
An account that never paired: no statement, no platform call (pinned).

**The handshake differs from §5 in three ways.**

- `anta.app` is taken **before** the database opens — first thing in
  `main()`, together with the lookup of `anta.refresh`, in one
  synchronous step. Taken after the open, a launch and a job that start
  together would miss each other, and overdue work tends to run exactly
  when the process comes up. A ping is answered at once; a forwarded
  read waits until the app has launched.
- On every resume the app takes its name again: a trigger that met the
  app too busy to answer within two seconds removes it.
- A run cannot be stopped inside an alert pass: a yield, the limit and
  the platform's stop take effect at the next step, and only the read is
  cut. A launch that has waited five seconds opens the database anyway.

**The run differs from §6 in two.**

- Step 4 is a whole alert pass before the read: it plans the successor,
  rolls the thirty-day horizon forward and decides "wanted" in one go. A
  run that is not wanted reads nothing and leaves no work behind; a
  wanted one passes again only if the read touched the calendar.
- Its dependencies are a registration of their own
  (`configureSharedRefreshRunDependencies`): the database, the note and
  folder repositories, the identity, the pairing and sync gateways, the
  scheduler and the alert gateway. No space service, no bloc, no
  lifecycle; `SyncEngine.autoStart` is never set and the app's engine is
  never built. Firebase comes up through the same
  `initializeFirebaseForSync()` the launch uses, and a QA build's
  preferences are namespaced the same way.

**Two notions of "depends", where §4 has one.** *Check-worthy* — what
schedules the phone's own check: a fire time armed, the category case,
or an alert of mine on a partner's event that can still occur (a one-off
not past its day, a repeating event not past its end; judged from the
event's dates, never by walking its rule). *Poke-worthy* — what makes a
run read when a message started it: that, or any enabled alert of mine on
any partner's event the phone holds, a past one included — the partner
may just have moved it into the future. A successor is planned only when
check-worthy, so an alert on a past one-off keeps no check alive. The
job's input data carries its cause (`check` or `message`).

**The launch's wait** ends on the run's answer, on its name being gone
(looked for every 250 ms) or at five seconds — a yield sent to a run that
has just closed costs the launch under half a second.

**What a run found is kept** (decision f) in one `sync_metadata` row,
merged by id, twenty of each kind at most, the leave's partner name with
it; and the database's name is added to a small list in preferences, so
the app knows from memory whether to look — an install that never kept a
notice runs no statement for it at start or resume. The listener takes
them at start and on each resume, in one transaction, and says them by
its own rules. Two catches: a database renamed between the run and the
open loses its notice, and a run beside a live but unresponsive app is
told only at the next cold start.

The engine's seam is one method, `readSharedWhileAway()`, used by the
forwarded read and by `SyncEngine.awayFromApp()` — an engine that is
never started and is "not in front" from its first moment.
`DatabaseManager.schemaVersionOfFile` reads a file's schema through
read-only SQLite without opening it; an unreadable file counts as a
mismatch.

**Two slots** (from the review and the first runs on a device). The
check lives under two unique names, `shared-refresh` and
`shared-refresh-2`, one at a time. Replacing a unique work cancels it, a
running one included: a run that scheduled its successor under its own
name was stopped by the platform right after it had planned, before it
read anything. So a run writes only the slot it is **not** in — its
task's name tells it which — and the app, which runs in no work, writes
the first and takes the second off; a cancel asked from a run leaves the
running slot alone. The successor is still planned before the read.

**A forwarded read names the work that forwards.** The trigger's question
to the app carries its slot (`[verb, reply, the slot's work name]`). The
app names that work as running for the read and for the alert pass after
it — which forgets the check that work was, or the pass would find its
plan "already scheduled" and leave the phone with no successor — writes
the next check into the other slot, and gives the work back once the
plan has reached the platform.

**A message's work stands in neither slot** (decided where slice I and
slice J met). It runs under a third unique name,
`shared-refresh-message`, so what is scheduled while it runs replaces no
running work, and the check that stands is not the work that asks. It is
told no slot (`SharedRefreshCause.standsIn`) — in its own run, and in a
read it forwards, which says nothing of a slot: nothing is forgotten, and
the pass replaces the standing check only if the read moved the plan.

**Proven on two fleet guests** (the share suite's flows `04j`–`04l`,
2026-11-13, on the two-slot build; Android API 36):

| Case | What was seen |
| --- | --- |
| B1 | Nothing shared that can ring: no work stands, nothing is armed. |
| B11 | The app open but sent home: the forced work ends `forwarded`, and a successor stands eleven hours and fifty-nine minutes ahead. |
| B4 | The process ended with `kill -9`, the owner moves the event an hour: the work starts the process, ends `read`, and both tiers — the reminder and the alarm — stand an hour later on every armed day, the app never opened; a successor stands. About three seconds for the run. |
| B5 | The owner stops sharing the event: the run ends `read`, nothing is armed, no work is left; the next launch says "{name} no longer shares Lifting session. Your alert is off." |
| B10 | The work started on a dead process and the app launched at once: the launch succeeds and both tiers end an hour later. |

Three things the device taught the harness, kept in the `qa-emulator`
skill: on API 36 WorkManager's job appears under a namespaced header;
`am kill` is read as a force-stop, after which a forced work does not
run (`run-as … kill -9` is the app dying by itself); and a guest's
sign-in account, held in memory, has to be set again after its app is
restarted.

### The Firebase packages (2026-11-13)

`firebase_core` 5.1, `firebase_auth` 7.0, `cloud_firestore` 7.1,
`firebase_messaging` 17.0 and `firebase_app_installations` 0.5 (decision
m). No Dart line had to change; the debug APK and the Windows build
build; the rules suite is green. `firebase_messaging` registers nothing
by itself: auto-init is off in the manifest and in `Info.plist`, so a
phone that is not paired never talks to FCM. On the Mac, `flutter pub
get` and a build let SwiftPM take the new Apple SDK (13.1); iOS push
itself needs capabilities this pass does not add. Two failure paths
changed underneath: a signed-out listener now hears one `null` where it
heard two, and a failed count comes back with its code — so the shared
reader's count, offline, now throws "unavailable" where it logged and
went on.

### Slice J — the app's side (2026-11-13)

- **The rules.** `rewritesOwnPush()` in the pair's update rule — only
  `push`, only the caller's own uid, at most five devices each `{id,
  kind, at}` validated by position, `at` not after the request's time;
  on an ended pair a member may only take devices away — and
  `config/{doc}`: a signed-in `get`, nothing else. `push` cannot be
  created with the pair. Eleven rules cases beside the 163.
- **`PushAddressSource`** over the installation-id API
  (`onRegistered` before `register()`), behind a small seam over the two
  plugin objects. `giveUp()` drops the cached address at once,
  unregisters **and deletes the installation** — `unregister()` alone
  keeps the id, so only the deletion makes the next address a new one
  (decision n). A deletion that fails is **owed**: remembered for the
  install, paid at the next launch with a network and before any new
  registration, so an address is never handed out twice. An address is
  marked held from the moment a registration is asked for, and a name
  that belongs to a registration from before a give-up is ignored.
- **`PushRegistry`** works off what the pairing gateway already hears
  (`PushPairingGateway` wraps it) rather than a subscription of its own,
  which would have built the share service at launch for everyone. It
  removes its entry before a sign-out — the rules need the session — and
  the whole of that leave, the wait for a registration in flight
  included, is bounded by five seconds. It leaves whenever this install
  holds an address, relay known or not; when the partner ended the pair
  while the app was closed it removes its entry from the stored pair;
  with five devices of mine in the map the write drops my oldest; it
  never compares the phone's clock with a server stamp (the weekly
  rewrite goes by when this install last wrote; a stale device is one
  sixty days older than my newest); after a leave nothing is written for
  that account until a pair is heard for whoever is signed in then. A QA
  build and the run without the app get the no-op set.
- **`PushRelay`**: `config/push` at most once a day, an hour after a
  failed read; `https` with a host only; one pending poke per pair, the
  first after a quiet minute at once and later ones merged, urgent
  winning; sent at once when the app leaves the front; ten seconds;
  never awaited.
- **The trigger.** `SyncDao.oweSharePoke(pairId, urgent)` — one entry per
  pair, raised and never lowered — written with: a batch that landed with
  a granted row (in its acknowledgement's transaction; a batch of private
  rows writes nothing); the three mark writers and their clears; a folder
  or a note moved across a shared folder's edge; an event's category
  change and `reassignCategory`; a shared category deleted; a mark that
  arrives by a merge from my other device. After a drain — and after the
  run's shared read, so a session's first run can know it is paired — the
  pusher returns with no statement when no relay is known or the database
  is not paired; else one keyed read, and when something is owed and
  nothing of the shareable tables is still to be tried, it takes what is
  owed in one transaction and pokes each pair. A parked entry holds
  nothing back. A deleted shared row's tombstone carries its grant, so a
  delete owes through the first rule. Ending the pair pokes directly.
  The owing is cleared at an unbind and stripped from a database copy.

- **Receiving.** `PushReceiver` over a seam on the messaging plugin
  (`PushMessaging`). Nothing is listened to and no handler is registered
  unless this install holds an address — never under a QA build, off
  Android, or in the run without the app. *In front*: a message for the
  open database's pair is gathered for two seconds and becomes one
  `SyncEngine.readSharedNow()`; another pair, an unknown kind or a
  malformed message is ignored. *Not in front*: the plugin's background
  isolate runs a top-level handler that opens no database and resolves no
  service — it hands the work to WorkManager under a third unique name
  (`shared-refresh-message`), cause `message`, the pair in its input
  data, appended behind a message-job already running so that a second
  message is neither dropped nor cancels the first. The job ends without
  reading when the pair is not the open database's (case B13). The
  plugin keeps the handler's handle in its own preferences across
  processes, but a new build can invalidate a raw handle, so it is handed
  over again in every process that confirms an address. WorkManager is
  used rather than the plugin's own background isolate because that
  isolate lives on between messages, and a run needs a clean one.
- **Expedited on Android 12 and later** (decision o). The handler's
  isolate cannot ask `MainActivity` for the API level, so the app's
  isolate stores the answer in the step that hands the handler over —
  `SettingsKeys.pushExpeditedWork`, install-wide, written before the
  hand-over in every process that takes an address into use, from the
  alerts channel's `sdkInt` (`AndroidAlertGateway.sdkLevel`,
  `kExpeditedWorkMinSdk` = 31). The handler reads it with one preference
  read, after it has seen that the message names a pair; missing,
  unreadable or failed is "not expedited", the direction that can never
  cost a notification. Out of the expedited quota the work runs as an
  ordinary one. Not proven on a device: a QA build never receives a
  message.

**The review** (Fable): the rules read sound and the wire matches the
relay; eleven defects reproduced in the registry, the address source and
the trigger — a sign-out that could hang on the platform, an address
reused after a failed give-up, an owed poke thrown away for want of a
pair id, one stuck private note holding every poke back, a run that sent
a shared row and then failed never poking for it — all fixed as above.
Nothing here has run on a device: registration, the deletion yielding a
new id, a sign-out in airplane mode and a call to a live relay are the
owner's phone checks.

### The relay (2026-11-13)

`backend/push-relay/` — `src/relay.js` (the logic, its dependencies
injected, nothing needed at run time but WebCrypto), `src/index.js` (the
Worker's entry: one relay per isolate, `ctx.waitUntil` and the
rate-limiting binding handed in per request), `wrangler.toml`, and two
suites on Node's own runner: 105 cases against the logic with Google
faked, and one that runs the real entry under `workerd`. Built by one
implementer, read by a Fable reviewer, fixed, and the reviewer's 37
mutations each now fail a test. Not deployed; nothing here has called
Google or Cloudflare.

**What the review changed** (all in §7–§8 above as they now stand): the
keys moved from the shared edge cache to the isolate's memory and a
forced refetch is limited to one a minute; the answer goes out before the
sends; the rate limit uses Cloudflare's binding, with an hourly cap in
memory; outages are logged and answered 503 instead of looking like
refusals; an entry names its kind (`fid` or `token`); an ended pair is
served for a day; every outbound call has a deadline and follows no
redirect. And one thing no relay can fix, which decision n answers on the
phone: an address is not bound to an account.

**Decided in the build.**

- A wrong method on `/poke` is 405 with `Allow`; a misconfigured Worker
  answers 500 before it looks at the caller, so the answer says nothing
  about anyone's devices.
- A credentialed call uses `redirect: manual` — Workers do not implement
  `error` — and a 3xx is then a failed answer.
- A failed key fetch is not repeated for ten seconds; a failed token
  exchange not for thirty. A newly rotated Google key can be refused for
  up to a minute after the last fetch.
- If the binding fails, the poke is let through with one log line and the
  hourly cap still holds.
- The same id registered both as `fid` and as `token` is sent twice.

**Not verified here**: the rate-limiting binding on the free plan (the
dry run accepts it; if the deploy refuses it, delete the `[[ratelimits]]`
block and the in-memory limits remain), `waitUntil` on the real edge,
FCM accepting the message, the service account's role.

### Open at the pause (2026-11-13)

The session was cut by an outage; the tree was left at the last state
that passed the whole gate. What follows is **not in the tree**. The
unfinished work is saved as patches outside the repository (the share
record's §16.9 names the folder).

A Fable reviewer read legs 1–3 of the check and ruled fourteen things.
The first two are built and proven above (the forgotten work, two
slots). The other twelve are decided and not built — a patch holds 3 to
7 mid-way, unverified:

| # | Ruling |
| --- | --- |
| 3 | What the run arms is byte-identical to what the app would arm, and it does nothing that needs the app: the app stores its arm context whenever its own pass computes it, the run arms with the stored one, and with none stored it runs no alert pass. The run never marks or shows "missed". Today the run's engine has no activity, so it loses the ring-volume floor, the 24-hour words and the reminders' grouping, and re-arms every standing entry. |
| 4 | A live app never gets a second writer beside it: three pings over six seconds before its name is called stale; the app takes its name again on a timer while in front; one marker both isolates read for "a database is being replaced" (a restore, an import, a download). |
| 5 | The run does none of the launch's repairs: it reads the active database's name read-only, and a download marker ends it. |
| 6 | A second run asks a live one to end and waits for it before it takes the name — with messages, two runs are ordinary. A message's run schedules with no slot, so no check may still be running when it does. |
| 7 | An end that leaves no next chance answers "retry": Firebase that failed to come up, an account not restored in time, a read that failed offline. Never for a cause that cannot heal by itself. |
| 8 | The never-started engine honours a stored quota pause; an away read merged into a pull that is cut is reported as not read. |
| 9 | A forwarded read that gave up is dropped, not run later. |
| 10 | The two lines at the top of `main()` are guarded; `anta.app` is removed when the engine detaches. |
| 11 | A pass that came with no shared read may bring the check nearer, never later. |
| 12 | `Alarm.init()` in the run re-sets every stored alarm, and a ring during a run is presented to the run's isolate: the owned fork needs a way to set and stop alarms from an engine that is no presenter. The pair's ending is a one-shot read in the run. The entry returns at once off Android. |
| 13 | A kept notice is cleared only once it was said (the reviewer of the notices found the same: an app closed before saying it loses it); taking it and dropping the database's name are one step; an event that left and came back is said as neither; a name whose database is gone is pruned. |
| 14 | The suites that are missing, and five tests that pass with the behaviour removed. |

Two more, from where the check and the relay met: a forwarded message
read carries its pair, and the app reads only when it is the open
database's (case B13 holds today only for a run without the app); and a
message's run beside a live check's run (ruling 6).

Not proven anywhere: a message arriving at all (a QA build receives
none), the expedited work in Doze, the relay on the real edge. A Fable
review of the receiving side and of rulings 3–14, once built, is owed
(§16.7 of the share record).
