# Shared Freshness — ANTA

**Status: BUILT AND REVIEWED 2026-11-13 → 14, COMMITTED `7803e07a`; the
rules are live since 2026-11-14, the relay is deployed (the owner's
first upload 2026-11-14, as Cloudflare's deployment list shows; again on
2026-11-22 with the pair read's field mask, version `20047acb`) — slice I
(the check) and slice J (the relay) of
`cloud-share-surfaces-roadmap.md` §16, and the finishing pass that
answered five reviews of them. §1–§11 are the plan; §12 says what is
built, block by block in the order it was built, and is the truth over
the plan above it — a later block over an earlier one. Its last blocks
say what is not promised and what only a phone or the deployed relay can
prove ("Still owed"); §9 is what the owner does before any of it can
run between two real phones.** This is the design
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

**As built, this section is superseded in four places** (§12): the check
stands under two unique names, one at a time, and a message's work under
a third ("Two slots", "A message's work stands in neither slot"); what
keeps a check alive and what makes a message's run read are two notions,
not one ("Two notions of depends"); the plan is remembered across
isolates and believed only where the platform agrees, and a pass with no
read never pushes a standing check later (R2 and its table, K1); a run's
ends and which of them retry are one table ("The ends of a run, as they
stand").

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

**As built, the protocol is wider than this** (§12): `anta.app` is taken
before the database opens and again on every resume, and the launch's
wait is bounded ("The handshake differs from §5 in three ways"); a live
app never gets a second writer — three pings over six seconds before its
name is called stale, the name taken again every ten seconds in front —
and a restore, an import or a download stands a marker every run
respects (ruling 4, H6); a run never takes the name over a live run
(ruling 6, with the table of who asked whom to give way); two
connections can still coexist for a bounded moment, so every connection
waits for a lock instead of failing, a name taken back is followed by a
catch-up, a step cannot hold the name past its limit, and a dead run's
name costs a launch one second, once (H1–H4).

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

**As built, the steps differ** (§12): a whole alert pass comes before
the read — it plans the successor and decides "wanted" — and the run's
dependencies are a registration of their own ("The run differs from §6
in two"); the run does none of the launch's repairs, opens an existing
file only and never creates the device id (ruling 5, N1); what it arms
is what the app would arm, and it is never the place a ring is shown —
its engine resigns as an alarm presenter first (rulings 3 and 12, R7);
"retry" is answered only for a cause that heals by itself, and a
message's work that asked three times in a row ends (ruling 7, R3); a
run whose read finds the pair ended gives the install's push address up
("After the review of the push client").

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
   `backend/push-relay/`. — DONE: on 2026-11-26 the Worker answers at the
   address step 4 names (a GET on `/poke` gets the relay's own 405).
2. In the Google Cloud console of the project: a service account with the
   role "Firebase Cloud Messaging API Admin" and nothing else; its JSON
   key → `npx wrangler secret put FCM_SERVICE_ACCOUNT`. The project's id →
   `wrangler.toml`.
3. The rules deploy (it carries `push` and `config/push`) — DONE
   2026-11-14, the rules alone, the rules suite green on them first (177):
   `firebase deploy --only firestore:rules --project alexs-note-tracking-app`.
   The indexes were live already and have not changed.
4. In the Firebase console: the document `config/push` with one field,
   `relay`, the Worker's URL. — DONE 2026-11-14 (read back on 2026-11-26:
   created that day at 15:01 UTC, its one field naming the Worker).
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

### After the review of the check — rulings 3 to 14 (2026-11-13 → 14)

A Fable reviewer read legs 1–3 and ruled fourteen things; 1 and 2 are
"two slots" and the forgotten work above. One Fable implementer built 3
to 14 in six legs, each ruling pinned by a test shown able to fail.
Where this differs from §4–§6 and from the blocks above, this is the
truth.

**What a run arms is what the app would arm (3).** The Android binding's
arm facts — the ring volume's bucket, the resolved language, the 24-hour
clock, whether reminders are grouped, the pixel ratio — are stored by the
app's own pass whenever it computes them (`AlertArmFacts`, one
`sync_metadata` row; an identical one costs no write). A pass away from
the app (`AlertScheduler.awayFromApp`) adopts the stored facts instead of
asking an activity that is not there. With none stored or readable the
pass is refused: the run plans no successor, reads nothing and ends
`noArmContext`, no retry — the app's next pass stores them and plans the
check. Away, no late fire is settled: nothing is marked or shown
"missed", and no delivery evidence is taken. Pinned: over an unchanged
calendar, with every activity-only call failing, a pass away makes no
platform call and writes no registration.

**A live app never gets a second writer (4).** Three pings over six
seconds before `anta.app` is called stale. The app takes its name again
on every resume and every ten seconds while it is in front, and a
re-take asks a run in flight to end. And one marker both isolates read —
`DatabaseReplacing`, in the preferences beside the download marker: a
restore, an import and a download stand it for their length; a trigger
asks it after its preferences are namespaced and before the database's
file is looked at, ends `suspended`, and never clears it. No retry for
that end: a marker a dead process left would loop until the next launch,
whose `main()` clears it.

**The run does none of the launch's repairs (5).** It reads the active
database's name without the manager's recovery, and
`DatabaseManager.recoversAtStart` is false in the run's isolate from
before it builds anything — or a download marked between the marker
check and the open would be "recovered" by a background isolate.

**A run never takes the name over a live run (6).** A free name is taken
in the caller's turn. A held one is pinged: a live holder is asked to
give way and waited for, five seconds at most; a dead one's name is
removed. Still held, the trigger ends `busy` (retry) and opens nothing.
The run's port answers pings. So a message's run beside a live check's
run begins only after the first has stopped its read and closed — no
check's work is running when it schedules.

**Who asks a run to give way decides how it ends.** Two verbs: `yield`
is the app's (a launch, or its name taken back), `yield-to-run` a later
run's; the app asking at any moment wins.

| Asked by | The run was | Ends | Retry |
| --- | --- | --- | --- |
| the app | either | `yielded` | no — the app reads |
| a run | the check's | `gaveWay` | no — its successor is planned |
| a run | a message's | `gaveWayOwed` | yes — or the change that started it waits for the app |

A message's work gives way three times in a row at most
(`kSharedRefreshGiveWayAttempts`), counted in the preferences: the
`workmanager` plugin hands no attempt count to Dart. Any other end of a
message's run clears the count; a count that cannot be kept is no retry.
A check's run never retries, so two works cannot keep ending each other.

**"Retry" only for a cause that heals by itself (7).** Firebase that did
not come up, or an account not restored in time, is `sharingUnknown`
(retry) and no longer "not sharing". A read is *owed* — `readFailed`,
retry — for offline, a spent quota or an unknown failure, and for a run
skipped by a restore, a stopped engine, a pause, a pending first merge or
a rebind. Signed out, another account, unbound, an outdated app, no
access, a deleted space, a refusal by the rules and malformed data end as
a read: a retry would loop (`healsByItself` on both enums, exhaustive,
with a table test over every value). The engine holds "owed" from the
asking until the reader lowers it in its `finally`, so a read merged into
a queued pull that a leave cut — never made, with nothing wrong reported —
is still owed. Only the run that carries the away read lowers it.

**The stored quota pause holds for a run too (8).** An engine that was
never started answers an away read `paused` (owed) while the stamp holds
— the engine's own rule, an hour at most — and only reads the stamp.

**A forwarded read that gave up is dropped (9).** The app counts the
asker's patience by the trigger's own limit, sixty seconds; a read still
waiting for the launch when it is over is never begun.

**The launch's step cannot fail the launch (10).** `beginLaunch` never
throws: a failure is logged, the port dropped, no name held. `anta.app`
is given up when the engine detaches and taken again if it comes back.
The step is four synchronous registry calls.

**A pass with no read never pushes the check later (11).** With a check
standing ahead, such a pass may bring it nearer; `readMade()` is spent
by one pass. A check whose time has come is planned again — which is
what keeps the chain alive when a work was consumed without telling the
app.

**A message's forwarded read carries its pair (B13).** The read message
is `[verb, reply, slot word, pair]`. The app reads only when the open
database is in the named pair — the rule the run's own `shares()` asks —
and otherwise answers "done": nothing read, no pass, no retry.

**A run is never the place a ring is shown (12).** With no app alive the
run's engine was the only one a ring could be reported to — its silence
timer dying with it — and `Alarm.init()` re-set every stored future
alarm each time a run started. The owned fork gains its tenth patch:
each attached engine carries `presents`, true until that engine's own
Dart says `resign` on a small channel beside the generated bindings, and
resigned engines are set aside before the host picks whom to tell
(`AlarmPlugin.presenters`). The run starts the fork with
`Alarm.initWithoutPresenting()`: it resigns, opens the fork's storage and
does nothing else — no check of stored alarms, no trigger handlers, no
fallback timer. So a ring, a stop and a host event reach the app's
engine if one lives, and otherwise nobody, exactly as in a process with
no engine; the run still sets and stops alarms. The gateway is built
with `presentsAlarms` true at launch and false in the run; the scheduler
does not know. The pair's ending is asked in the run as a one-shot read
(`PairingService.endingRead`), with no pairing service built and no
listener attached. Off Android the entry returns at once.

**A kept notice is cleared only once it was said (13).** Reading the
kept notices clears nothing. The listener reads them at start and on
each return and tells the store what it has said — and what it dropped
as undone at the moment of saying, which will never be said; only that
is forgotten, by kind and id, and what a run kept in between stays for
its own turn. An app closed before the bar could show, under a dialog or
an alert, says it at the next start. A notice still waiting when the app
returns is not said twice. The row and the list of names can no longer
drift apart: a run names the database before its row and again after it,
and taking a name off looks at the row once more. An event that left
with my alert and came back before anyone was told is in neither list.
A name whose database is gone is pruned at a read. An install that never
kept a notice still runs no statement, opens no database and looks for
no file at start or on return (pinned).

**The suites the review asked for (14)** exist: the run's real steps
taken to their end with and without a stop
(`shared_refresh_run_steps_test.dart`), a launch and a run that start
together in both orders, what `main.dart` calls
(`shared_refresh_wiring_test.dart`), the app's own read with a message's
pair, and each of the five tests that passed with the behaviour removed
now fails without it.

**Only a device can show**, and none has yet: that a closed-app check
over an unchanged calendar re-arms nothing on a 24-hour phone with a
quiet alarm stream; that an alarm stopped natively is not posted as
"Missed" by a run; that a ring during a run shows the alarm page with
its Silence-after intact; that a main isolate stalled for a few seconds
still gets the forward; that a marker the app wrote is read by the
worker's isolate; a check forced mid-restore ending `suspended`; two
real works overlapping; airplane mode during a message's run; whether
Android delivers `detached` before the engine goes; an app killed while
a kept notice waits saying it at the next launch.

### After the review of the handshake — H1 to H11 (2026-11-14)

A second Fable reviewer read the two isolates' handshake as built
(rulings 4, 5, 6, 9, 10 and the give-way) and found sixteen things: no
lost data, but windows in which two connections write side by side, a
name held by something that will never answer, and ends that stop the
chain. Eleven rulings answer them, built by the same implementer, each
pin shown able to fail. Where this differs from the block above, this
is the truth.

**Two connections can coexist for a bounded moment, so every connection
waits (H1).** `PRAGMA busy_timeout`, five seconds
(`AppConstants.sqliteBusyTimeout`), in `configureSqliteConnection` — the
app's connection, the run's, every isolate's. A writer that met another's
lock used to fail at once. Nothing else of the connection changed.
Pinned by a second writer in another isolate that waits for the first's
commit and then writes.

**A name taken back is followed by a catch-up (H2).** When a resume or
the ten-second tick takes `anta.app` again and really took it — the app
had lost it, called stale during a stall — a run may have written behind
the app. The app waits for a run in flight to close, then reloads
wholesale (`AppSyncApplyHooks.afterWritesBehindTheApp`: the note and
folder caches dropped, the share marks, the whole event store with the
alert services, one alert pass), reads the share on its own engine and
runs a quiet pass: once, each step in its own guard. The same after an
engine that detached came back. A tick with the name standing is still
one registry lookup and nothing else.

**A step cannot hold the name past its limit (H3).** At the limit, or
when the platform stops the work, the trigger arms a grace of five
seconds (`kSharedRefreshAbandonGrace`). A step that is still not back is
left where it is: the database is closed under a bound of two seconds
(`kSharedRefreshAbandonCloseBound`), the name is given up, and the work
ends `abandoned` (retry). A step that returns after it was left takes no
writing step more. Before, a native call that never returned kept
`anta.refresh` for the life of the process and every later run ended
`busy`.

**A dead run's name costs a launch one second, once (H4).** The launch
pings and asks in the same turn. A holder that has not answered the ping
in a second (`kSharedRefreshDeadRunAfter`) is a dead run: its name is
removed and the launch goes on. One that answers is waited for as
before, five seconds at most.

**A check's run cut before its plan stood is retried (H5).** Asked to
give way before its alert pass returned, a check's run has planned no
successor: it ends `gaveWayOwed` (retry) under a count of its own, three
in a row at most (`shared_refresh_check_gave_way`), then `gaveWay`. The
message's work counts in another key, so one work's ordinary end cannot
clear the other's row.

**The marker (H6).** It is cleared on a resume too, when nothing of the
app's own is in flight (`DatabaseReplacing.clearLeftBehind`) — a marker
a crashed import left no longer suspends every run until the next cold
start — and a clear the store refused is owed and tried again. A store
that cannot be read says neither "standing" nor "clear": the run ends
`replacingUnknown` (retry), apart from `suspended`.

**The ten-second tick runs only where a trigger can exist (H7).** A
check was ever planned (`sharedRefreshPlanned`) or a push address is
held; an account that never paired runs no timer. Planning the first
check starts it. A store that cannot be read keeps the name, the safe
side.

**Every other end clears the count (H8)** — a forwarded read and `busy`
included. It costs each trigger end one load of the preferences in the
trigger's own isolate.

**The active name is re-read (H9).** `peekActiveDatabaseName` reloads
the preferences first: a switch the app made after this isolate's first
read is seen.

**The rest of the handshake (H10).**

- The marker is asked three times: at the first look, before the alert
  pass, and before the read. Found later, the run ends `suspended` as at
  the first look; the replacing app's own pass plans the check.
- The run opens **existing only** (`AppDatabase.opensExistingOnly`): it
  never creates and never migrates. Drift opens SQLite itself, so the
  refusal stands at the two places app code is in front of it — the
  look for the file in the turn before the connection is made, and both
  migration callbacks, which Drift calls before it writes anything. The
  run ends `noDatabase` or `schemaMismatch`. A file removed between the
  look and the open is created by SQLite as an empty database and left
  so: nothing is created in it, and the app's own open treats it as it
  treats any new file.
- Taking the name answers what the registry answered: a name the
  registry refused was not taken.
- The platform stopping the work during a forward ends the wait at once
  (`cut`, retry); the app goes on reading for itself.
- The app stops counting a forwarded asker at fifty-five seconds
  (`kSharedRefreshForwardPatience`), five under the asker's own limit,
  so the two cannot disagree about a read that began in the last second.

**Only a device can show**, beyond the list above: that WorkManager gets
its answer and tears the engine down after `abandoned` with a native call
still hung, and whether two seconds close a database that is the thing
hung; a live run whose isolate is blocked for over a second losing its
name while it holds the database — the launch then opens beside it,
covered only by the busy timeout; whether five seconds are enough under
real contention on device storage; what a person sees of the reload,
read and pass after a real stall of the main isolate; no timer on an
install that never paired; a store that really refuses a remove.

### After the review of what a run arms and reads — R1 to R9 (2026-11-14)

The other half of that review: what a run arms, reads and plans. No lost
data and no "Missed" from a run; what was wrong was in the plan and in
the ends — one end stopped the chain silently, the plan's memory held
only inside one isolate, and several retrying ends had no bound. Nine
rulings and one more, the same implementer, each pin shown able to fail.

**The plan is remembered across isolates (R2).** What stands — per slot,
the instant it is due — is kept in the preferences
(`SharedRefreshMemory`, one key per slot, re-read each time) and written
at every schedule, every cancel and every work consumed; every isolate
plans against it. Before, the memory was one isolate's: each cold launch
planned from now and replaced a nearer check — opened every eight hours
with nothing read, the app starved the check for good — and a check that
was due and waiting for the network was cancelled by the next pass that
came with no read, minutes before the ring it was for.

| A pass finds | and would plan | It does |
| --- | --- | --- |
| a check standing ahead | a later one, no read made | keeps the standing one; no platform call |
| a check standing ahead | an earlier one | replaces it by the nearer |
| a check that is due and has not run | anything, or none | leaves it: it runs the moment its constraint is met. Cancelled only for cause — the database no longer shares |
| anything, after a read was made | — | plans from now |

A store that cannot be read plans as a first one: a nearer check may be
replaced once, and the chain goes on. Not taken: registering a due check
again under a "keep" policy at each pass, to restore a work the platform
lost — WorkManager re-enqueues its works after a force stop by itself.
An install that never paired is not asked the memory at all; one that
shares pays one read of the platform's store per alert pass (K3 below
says how it is read, K1 when the platform itself is asked).

**"Wanted but nothing stands" is not "not wanted" (R1).** A check's run
whose pass found a need and whose successor does not stand — the
platform refused the registration, or the pass never reported — ends
`failed` (retry). `notWanted` is only a pass that reported no need.

**Bounds (R3).** A message's work counts every retrying end, three in a
row at most, then ends `retriesSpent` (no retry): the unique work no
longer stays enqueued for good with later messages waiting behind it.
The check's work counts give-ways only — its retry chain and its
successor replace each other, and WorkManager's back-off bounds the
rest. A first merge still pending is not owed by an engine that was
never started (`SyncRunSkip.healsFor`): the app's launch completes it. A
binding that presents nothing and did not come up adopts nothing: the
pass is refused and the run ends `noArmContext`.

**Each ask answers for its own read (R4).** The engine raises a token
per away read and lowers only what the run carried; the answer travels
in the asker's own report (`SyncRunReport.awayReadOwed`). One away
read's run can no longer lower the flag another raised.

**The forwarded path reports its pass (R5).** On the app's side a pass
that fails answers the asker "failed" (retry), and the read is spent in
a `finally`, so no later unrelated pass moves the check on its strength.

**An account that never paired pays nothing for the arm facts (R6).**
They are worked out, read and stored — and the SDK level asked on a
pass — only where a run can exist
(`SharedRefreshAvailability.runsCanExist`: a check was ever planned, or
a push address is held). They are stored when the first check is planned
and as the app leaves the front, so a run does not find them missing.

**The ring's snapshot is fresh, and the work resigns first (R7).** An
away pass asks which alarms sound right after it adopts its context, not
at the run's start; the work resigns as a presenter first thing in its
entry, before Firebase and the database, so no ring is reported to an
engine that will not show it.

**A forwarded message read asks the worth first (R9).** With the app
alive and not in front it reads only when the last pass found a message
worth a read, as a run does; in front, or before any pass has reported,
it reads.

**A run never creates the device id (N1).** Under the existing-only open
a missing `device_id` ends the open as `noDatabase`, and the look comes
before anything that could write.

**The tests the review asked for (R8).** The fork's three Kotlin cases
go through the one function the getter is (`presenterAmong`); the
adoption pins the language and the pixel ratio; the review's four probes
are suite cases (`shared_refresh_memory_test.dart`).

**Recorded, not changed.** A facts write that failed, and an update that
changes the arming grammar, make one run re-arm every standing entry —
what the app would arm. Late rows stay pending while the app stays
closed; the next open issues one cancel per row older than a day. "No
platform call over an unchanged calendar" holds over the test gateway: a
real run's start makes about ten (the resign, the ring lookup, the
plugin's start, the channels), and each away pass one ring lookup.

**The ends of a run, as they stand.**

| End | Retry | When |
| --- | --- | --- |
| `read`, `notWanted`, `forwarded` | no | the work was done, was not needed, or the app did it |
| `yielded` | no | the app asked; the app reads |
| `gaveWay` | no | a run asked a check's run whose plan stood, or the check's give-way count is spent |
| `gaveWayOwed` | yes | a run asked a message's run, or a check's run before its plan stood |
| `retriesSpent` | no | a message's work asked for a retry three times in a row |
| `busy` | yes | another run holds the name and did not give way in time |
| `cut` | yes | the limit or a platform stop, the step back within the grace |
| `abandoned` | yes | the same, the step not back |
| `readFailed`, `forwardFailed`, `failed` | yes | a read that is owed; the app's read or pass failed; a step threw, or a needed check does not stand |
| `sharingUnknown`, `replacingUnknown` | yes | Firebase or the account not up yet; the marker's store unreadable |
| `suspended`, `notSharing`, `noArmContext`, `noDatabase`, `schemaMismatch` | no | nothing a retry would change before the app is opened |

**Only a device can show**: that WorkManager holds a due work for the
network and re-enqueues it after a force stop; a run's writes to the
plan's memory read by the app's next pass, and the reverse; the resign
at the entry closing its window; `retriesSpent` followed by the next
message's work; the facts stored as the app leaves the front on a
freshly paired phone.

### After the closing review of the check — K1 to K8 (2026-11-14)

A third Fable reviewer read the two fix passes as new code. No lost data
and no way for a run to create or migrate a database; four things to fix
before the phones, the rest low. Eight rulings and three follow-ups, the
same implementer. Where this differs from the blocks above, this is the
truth.

**The plan's memory is believed only where the platform agrees (K1).**
The memory could say "a check stands" with no work behind it — and under
R2's own rule a check that is due is never replaced, so no check would
ever be planned again. The ways there: Android's backup and device
transfer restore the preferences file onto a new phone (only `device_id`
is left out) and never WorkManager's works; a work served by an app in
which sync did not come up was written off only in that isolate; a work
the platform lost. So before a standing entry is the reason to schedule
nothing, the scheduler is asked whether the platform holds that work
(`SharedRefreshScheduler.stands`, WorkManager's
`isScheduledByUniqueName`: enqueued or running) — once per isolate for an
entry ahead, once more when it is first found due. "No" drops the entry
and the pass plans as a first one; "cannot tell" trusts the memory. An
entry this isolate scheduled itself is not asked about, and an install
that never paired asks nothing.

**Every shared read made to its end is a read made (K1) — for the pass
that follows it.** In front, forwarded, or a run's own: the reader says
so (`SyncEngine.onSharedReadCompleted`) and a pass within two minutes of
it (`kSharedRefreshReadPassWindow`) plans from now — R2's fourth rule
now holds in every isolate. A read that failed, was cut or was skipped
is not one. Later than that the read counts for nothing: a read that
changed nothing is followed by no pass, and its flag, left standing,
made the next morning's resume replace a check that was due and waiting
for the network by one twelve hours out.

**A run never works out or stores arm facts (K2).** A message's run that
planned the install's first check stored the facts of its own headless
engine over the app's — no volume bucket, the dispatcher's clock style —
and every later run re-armed everything under them. The quiet store does
nothing away from the app; a run only adopts.

**No preference is re-read by reloading (K3).** The plugin's `reload()`
awaits the platform's map and then replaces the whole cache, so a write
the app made meanwhile was gone from its own copy: a restore's marker
left standing after it ended, the active database's old name read back.
A key another isolate may write is read **fresh from the platform's
store, the cache untouched**, through one helper
(`lib/services/fresh_preferences.dart`) — the plan's memory, the marker,
the counts, the active name's peek, the kept notices' names — in both
isolates; no `reload()` is left in `lib/`. The marker's scope removes it
unconditionally at its end. For this the app depends on
`shared_preferences_platform_interface` directly (it was a test
dependency).

**A wrong "dead" verdict is harmless (K4).** The one-second bound of H4
stays, and with it the chance that a live run, busy for longer, loses
its name while it holds the database. So a launch — or a re-take — that
took a holder for dead on silence alone owes one catch-up (H2) once the
old patience has passed, four seconds later; a holder that answered, or
none, owes nothing. A run gives `anta.refresh` up only while the name is
still its own port, so a run declared dead never removes a later run's
name; it ends at its next step boundary and takes no writing step more.
For the length of the step in flight the busy timeout (H1) is what
stands between the two writers.

**A step that returns after it was left cleans up (K5).** An open that
lands after `abandoned` closes what it opened and writes nothing off in
the memory: the end was a retry.

**The rest (K6–K8).** A binding that did not start refuses the pass on
the nothing-to-arm path too (`noArmContext`, not a throw). The catch-up
does nothing while a database is being replaced and never runs twice at
once; an engine that detached is not in front. The timer's tests go
through an open gate.

**Follow-ups.** The count of a message's retries is
`shared_refresh_message_retries` (the old key, a transient count on
development builds, is not read). The arm facts are stored the moment an
address is first held (`FirebasePushAddressSource.onAddressFirstHeld`),
so the first message's run finds them. The Kotlin mutation turned two of
the fork's three cases red; the third cannot fail on the filter — the
app's engine holds an activity there and is picked by order.

**Recorded, not changed.** A write-off can land after another isolate's
schedule into the same slot: the memory then says none while a work
stands, and the next pass plans a first one, once. The run's ring lookup
only adds — an alarm that sounded and was stopped before the pass is not
armed over by that run. An install that never paired pays two or three
in-memory checks at launch, on resume and per alert pass: no statement,
no platform call, no timer.

**Only a device can show**: a phone set up from another's backup
dropping the restored entry at its first pass and planning a check;
whether a live run ever misses the one-second answer at a launch, and
the catch-up making good what it wrote; the engine's teardown after
`abandoned` with an open still in flight; what the app's own writes do
when the busy timeout expires.

### After the review of the push client (2026-11-14)

The receiving half of the client, its fix pass and everything built
since had been read by nobody but their builder. A Fable reviewer read
all of it — the phone's side, the seam with the check, the relay where
the client relies on it. No lost data; one stuck state, one promise not
kept across processes, and nothing on the phone that bounded what a
message costs. One implementer fixed the client; the check's implementer
built the seam. Both reviewers then read the fixes: most of their
findings were closed, one ruling of the lead's was taken back — the
minute's floor between a pair's runs with the app closed, below — and a
leg answered the rest. That leg was read once more: a work the platform
runs again comes back plain and held everything behind it, which a
final leg answered; and the device pass found what no suite could — a
QA build's run that could not start (the last paragraph of this block).
Where this differs from §7 and from "Slice J", this is the truth.

**The address.**

- **Its end is bounded** (`kPushEndDeadline`, thirty seconds):
  `unregister()` and the installation's delete each have a deadline; a
  delete that is not confirmed stays owed. A platform call that never
  answered used to stall the registry's one chain for the life of the
  process — no address registered again until a relaunch.
- **A later pair always carries a new address, across processes too
  (decision n).** The give-up looked only at what this process
  remembered; a phone that slept through the end of one pair and woke in
  another wrote the old address into the new pair and left its entry in
  the ended one, where the former partner could go on waking it. Now the
  pair `push_written` names is compared with the pair heard: the address
  is given up — made owed first, so a process that dies there still ends
  it — and the earlier entry removed, before anything is registered.
  "Owed" is read off the store wherever it is acted on — at launch,
  before a registration, at a give-up — because another isolate may have
  written it since this one loaded its copy; an app that had loaded its
  preferences before a run's give-up used to register with the delete
  still owed, and the next launch deleted the installation in use. Two
  orders stay as they were, recorded: ending the pair myself and signing
  out remove the entry before the give-up (a sign-out's token goes in
  five seconds). A process that dies between the two and then hears a
  new pair before any "no pair" writes the old address into the new
  pair; the old entry is gone, and the handler's drop of other pairs
  bounds what a former partner could do with what they know.
- **"Holds an address" means exactly that.** An owed delete alone
  attaches no listener and hands no handler over.
- **A run gives the address up when its pair has ended.** The run without
  the app has no registry by design, so nothing ended an address while
  the app stayed closed: for the day the relay still serves an ended
  pair, the former partner could wake the phone. A read the server
  answers "no pair" on a database that says it is paired
  (`SyncEngine.sharedReadFoundNoPartner`) now makes the run give the
  install's address up at the platform, and each later such run asks a
  delete that is still owed again. The app's next open removes the entry
  from the pair's document and clears `push_written` whether or not an
  address is still held. The rules let a device leave an ended pair — a
  member's own entry may go, never be added or changed
  (`rewritesOwnPush`; the rules suite's "an ended pair refuses an added
  or changed device and lets one leave"). A removal answered "not
  permitted" all the same clears the key too, so no later open asks
  again; an offline or unknown failure keeps the key and is asked again.
  The rules give "not permitted" for three causes the phone cannot tell
  apart: the pair's document went with a deleted account, its entries
  with it; the caller was signed out by the time the removal was asked;
  another account is signed in on this phone. In the last two the entry
  stays in the document, naming an address that was given up — dead, or
  its delete owed. An owed delete is paid at every launch, by a run
  whose read finds the pair ended, by a message's run that finds the
  database not sharing (that one pays what is owed and touches no held
  address — the open database may simply be another than the paired
  one), and before any registration. The run binds
  the address source for this and nothing else of push. A run that reads
  nothing — no alert of mine depends on what {name} shares — never
  learns the pair ended: there the handler's drop of other pairs and the
  relay's one day are the bound.

**Sending.**

- **A held poke goes only under the account it was asked under**, or is
  dropped with a line; a leave and an account closure flush what is held
  before the token goes (`PairedAccountCloser.beforeAccountGone`).
- **The relay's answers are told apart, each as wide as its cause.**
  403: that pair is not poked again under that account for an hour
  (`kPushRefusalHolds`) — the relay's own refusal is stable, an edge in
  front of it may not be. 429 and 503: `Retry-After` is honoured up to an
  hour (`kPushRetryAfterCeiling`) for that account, and pokes inside the
  pause are dropped — the other phone has its own check. 401: logged. No
  queue, no retry.

**Receiving.**

- **The handler.** Its isolate — the messaging plugin keeps one for the
  life of the process, with every plugin attached — first resigns as an
  alarm presenter, so a ring with no app alive is never reported to an
  engine that shows nothing: asked once per isolate, and until the host
  has answered each message waits on that one ask, two seconds at most
  (`kPushResignBound`). Then it checks the pair's shape, and reads what
  the app stored once, off the store (`FreshPreferences`).
- **A message for another pair costs one read of the store.** The
  handler compares the pair with the one this install's address was
  written for: any other is dropped there — no work, no engine, no
  database. With nothing written the hand-over goes on and the run's own
  check stands.
- **Not in front, one work per pair at most, the newest.** The handler
  notes a waiting work before the hand-over (`SharedRefreshMessageGate`,
  one preference key per pair, device state) and schedules nothing while
  a note younger than ten minutes stands: five messages before the work
  starts are one run. Every start of a message's work takes the note off
  before its first step, so a message that comes once the work has
  started hands over again — and that hand-over takes the place of
  whatever message's work stands: waiting, held on a back-off, or
  running. The stopped run hands nothing over, counts nothing and clears
  nothing; the newer run reads everything. The note is bounded in age
  and not checked with the platform.
- **Nothing spaces those runs.** A minute's floor between a pair's
  message runs was built and taken out again: the sender spaces its
  pokes exactly a minute apart, so an honest correction started inside
  the floor and was deferred as a plain delayed work — which a sleeping
  phone holds while the alert rings at the old time. What bounds a
  pair's messages is the one work, the drop of other pairs and the
  relay's rate. There is no backlog.
- **A message's work is never delayed and never comes back plain.** It
  is expedited where the platform allows that without a notification,
  else plain; a failed expedited hand-over is asked once more, plain.
  WorkManager never expedites a work it runs again after a retry, and
  the plugin's `update` and `append` both queue a new work behind what
  stands (read in the plugin's source and in WorkManager's bytecode) —
  so one retrying end on a sleeping phone left a plain work on its
  back-off, and every later message's expedited work waited behind it
  for a maintenance window. Two changes, one sentence — a message's work
  is always a fresh one. The handler's hand-over replaces what stands
  (above). And a message's work never asks the platform to run it again:
  an end that still owes the read hands a fresh work over behind the
  running one — the one policy that does not cancel the work that asks —
  a first attempt again, expedited as stored, and answers "done". Three
  such ends in a row end `retriesSpent` and hand nothing over; only when
  that hand-over itself fails is the platform asked to retry. The
  check's own work is untouched: its retry stays the platform's. Not
  taken: one plain retry kept as a last rung for a maintenance window —
  the check is that net.
- **In front, at most one read a minute** (`kPushReadFloor`, the
  receiver's, counted from when a read was asked): the first message in
  a quiet minute reads at once, and what arrives inside the minute
  becomes one read at its end. §7's "the engine's own one-a-minute
  floor" never existed; this is it. A read that fails there is not
  retried — the engine's own poll is the net. There is no urgent bypass:
  the message carries no urgency a phone can read — only FCM's priority —
  so an urgent change waits a minute at most. A bypass would need a
  field on the wire and a relay deploy; not taken.
- **What is not promised.** "The last change is never left unread" is
  not true as an absolute: a message's work that owed its read three
  times in a row ends (`retriesSpent`) and nothing stands for it — the
  check, the next message or the next open reads. Those three attempts
  now come back to back, where the platform's back-off used to space
  them by half a minute and more: a cause that outlasts a few seconds —
  the server unreachable though the network is up, the account not
  restored — outlasts all three. A hand-over the
  platform lost is covered again only when its note is ten minutes old
  and another message comes, else by the check or the next open; a work
  with no expedited allowance — Android 11 and older, the quota spent —
  waits out Doze; a message that arrives while a work runs starts the
  read over.

**Device state does not outlive the device.** Android's backup and
device transfer restore the whole preferences file onto a new phone;
only `device_id` is left out of them. So the preferences that describe
this install — the plan's memory and its gate, both counts, the
replacing marker, the four push keys, and the waiting notes, one key per
pair — are listed in one place (`DeviceState.keys` and `.prefixes`) and
stamped with the install's device id (`device_state_of`). The launch,
right after the database opens, clears them when the stamp names another
device, and stamps when there is none — so a backup made before this
build ever ran carries no stamp and is not cleared, which only the
development phones of these days can have; "Delete all data" takes the
stamp off with the id. Before, a restored
"delete owed" made a new phone unregister and delete its own fresh
installation at first launch, and a restored "address held" attached the
listener and ran the ten-second tick on a phone with no address. Not
device state, and left alone: the active database, the download marker,
the sync registry and its pending deletions, the kept notices' list, the
relay's cached address. (The keys' own doc lines say "never in a
backup"; that is true of the app's backup — the system's restores them.)

**What the pair's document shows the partner** — said here because §7
did not: how many devices I have, their sync device ids, their FCM
installation ids and when each was last written. The relay needs the
ids there to send; nobody but the two members and the relay can read
them, and an installation id is of no use without the project's own
credentials. **Open for the owner**: moving the addresses to a place
only their owner and the relay can read would hide them from the
partner, at the cost of a new rule, a relay change and a deploy.

**Recorded, not changed.** FCM may deprioritise high-priority data
messages that never show a notification — only real traffic shows
whether urgent pokes arrive in Doze. With the app in front the gate is
the open pair id alone; the engine's own gates then skip a read that
should not run. The address is install-wide and a leave is per open
database: with two databases the paired one's entry can name a dead
address until it is opened again. After two failures in a row — a
removal the earlier pair refused and a first write that timed out here
and landed later — `push_written` names the old pair while the entry
names the new, and the handler drops the new pair's messages until the
next answer in an open app rewrites it. The stored plan's question to
the platform that could not be answered is asked again at the next pass.
**Open for the owner, outside this record:** Android's backup also
restores the plugins' own stores — the alarm fork's stored alarms, the
notifications plugin's pending list — onto a new phone, where nothing is
armed; the alert pass's fast path trusts that list, so reminders on a
restored phone may not fire until it is rebooted. Older than sharing,
not traced here. And the alarm fork reloads its whole copy of the
preferences at every foreground and background change, in every isolate
that starts it (`packages/alarm/lib/service/alarm_storage.dart`) — the
hazard `FreshPreferences` exists for: a key written around a resume can
be missing from that isolate's copy until the next reload. Nothing in
`lib/` reloads; changing the fork is an eleventh patch, and the owner's
call.

**Found by the device pass, not by a suite: a QA build's run could not
start.** The work's entry resigns as an alarm presenter first (R7) —
which opens the alarm fork's storage, the isolate's first
`SharedPreferences.getInstance()` — and the run's first step then
namespaced the QA build's preferences, which the plugin refuses once
`getInstance()` has been called: the run ended `failed` before it read
anything, and three callers the fix legs had added threw the same in the
app's own isolate, so a QA build never wrote the plan's memory.
`QaMode.enabled` is a compile-time constant that no suite and no
production build turns on: production was never affected, and only the
share suite's `04k` on a guest showed it — red twice on the merged code,
green on the committed build. Now the namespacing is once per isolate
(`QaBootstrap.prefixOnce`) and comes first in both entries, before the
resign. The rule this leaves: **in an isolate that starts with no app,
nothing touches the preferences before the namespacing — and a change to
an entry's first lines is proven on a device, not in a suite.** Proven
so on 2026-11-14, on two fleet guests with a QA build of the fixed code:
the share suite green twice, 23 flows each, `04k`'s forced works ending
`forwarded`, `read`, `read` — the run without the app reads again, and
both tiers of the alert move — with none of those lines in the guests'
logs.

**Only a device or the deployed relay can show**: a real registration
and its end, the deletion yielding a new installation id, the background
isolate's hand-over to WorkManager, the expedited quota, Doze, the
relay's real 403/429/503 and `Retry-After`, a phone set up from
another's backup clearing its device state before the push objects read
it, a run's give-up really stopping messages, the resign's channel
answering in the messaging plugin's engine and how long it takes, that a
replace cancels a running work and its stop reaches Dart, that a work
appended from inside the running one starts as a first attempt and
expedited, the superseded run winding down beside the new one — and the
premise under K1, that WorkManager's "replace" leaves no earlier record
under a slot's name (plan a check, let it run, plan again, log the
answer).

### Still owed (2026-11-14)

Not proven anywhere: a message arriving at all (a QA build receives
none), the expedited work in Doze, the relay on the real edge, and every
line of the "only a device can show" lists.
