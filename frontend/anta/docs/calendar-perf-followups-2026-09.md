# Calendar perf follow-ups (2026-09)

**Status: shipped 2026-09-02.** Five small fixes to rebuild scope and cache
lifetime on the calendar page, found by reading rebuild subscriptions and
cache growth — no profiler run backs any of this, and no timings are
claimed. This file deliberately does **not** reopen
[calendar-performance-roadmap-2026-08.md](calendar-performance-roadmap-2026-08.md):
its Phases 0–5 stay closed and none of its claims were invalidated (its
`List.unmodifiable` items describe `eventsForDay`'s per-day lists, which stay
bloc-wrapped; its 5.6 section remains true of the bars). The day-rail label
relocation of the same date is a **separate accessibility fix**, recorded in
the rewritten Accessibility section of the v34 addendum in
[calendar-events-feature.md](calendar-events-feature.md) and the D11
correction in [day-rail-markers-roadmap.md](day-rail-markers-roadmap.md) —
only its perf side effect (`markerBuilder` now fills the rail/tint memos
first, so `_buildDayCell`'s lookups are cache hits) belongs to this list.

## 1. The panel's keyboard padding reads at the leaves

`CalendarBottomPanel.build` read `MediaQuery.viewInsetsOf` at its build root
and threaded `bottomInset` into all three panel modes. Correct, but the read
subscribed the whole panel element to inset changes, so every frame of the
keyboard animation rebuilt the mode bar, the day header, and the entry
construction along with the padding that actually needed the value.
The read now lives at the four leaf padding sites — the day summary's empty
state and its list ([day_summary_panel.dart](../lib/widgets/day_summary_panel.dart)),
the timeline's scroll view ([day_timeline_view.dart](../lib/widgets/day_timeline_view.dart)),
and the agenda's sliver padding ([upcoming_agenda_view.dart](../lib/widgets/upcoming_agenda_view.dart))
— each inside its own `Builder`, so an inset frame rebuilds exactly those
subtrees. Rows and entries are constructed **above** the `Builder`s, which is
what keeps the agenda's `_rowsFor` result `identical` across a show+hide and
the existing memo-guard tests meaningful. The `bottomInset` parameter is gone
from all three mode widgets.

## 2. A page route over the calendar gates the keyboard collapse

Opening the keyboard in the note editor collapsed the **buried** calendar
grid to a week: `_KeyboardInsetProbe` reads the inset in
`didChangeDependencies`, and a buried route's subtree still receives
`MediaQuery` dependency notifications, so it publishes inset frames whichever
route is on top. `_CalendarViewState` (already `RouteAware`) gains
`_routeCovered` — set in a new `didPushNext` override, cleared in
`didPopNext`, which then re-runs `_handleKeyboardInset` so a still-open or
just-closed keyboard is folded in on return. While covered,
`_handleKeyboardInset` returns early. Scope, precisely: this gates **only the
keyboard-inset pathway** — BLoC-driven rebuilds are untouched — and
`PopupRoute` sheets never trip it, because `RouteObserver<PageRoute>` fires
only between page routes. That asymmetry is the point: the coupled collapse
exists *for* sheet keyboards, and it keeps working for them.

## 3. The resolver-output memos are pruned to ±3 months

`_barsOutputCache`, `_tintOutputCache` and `_railOutputCache` were cleared
only wholesale, on `_outputGeneration` mismatch. Page across months with
stable settings and no mismatch ever fires, so the three maps grew one entry
per visited day, unbounded. `_evictColdResolverOutputs` now prunes all three
to ±3 months around the focused month (`_outputCacheWindowMonths = 3`),
running on genuine month change — the year-or-month `listenWhen` — in the
**same** `BlocListener` that schedules the neighbour-month prewarm. This
mirrors `CalendarBloc._evictColdDayCacheEntries` (`_dayCacheWindowMonths`,
also 3), and the prewarm's radius-1 reach stays strictly inside the window,
so nothing just warmed is evicted before it is read. The generation-mismatch
clear survives unchanged; the pruning is bounded upkeep on top of it, never a
replacement for it.

## 4. `DateFormat`s are cached per locale

Two formats were constructed on every rebuild of their headers:
`DateFormat.yMMMM` in `_CalendarTable`'s `headerTitleBuilder` and
`DateFormat.MMMMEEEEd` in the day summary's header. Both are now static
per-locale maps (`_monthYearFormatCache` in
[calendar_page.dart](../lib/pages/calendar_page.dart), `_headerFormatCache`
in [day_summary_panel.dart](../lib/widgets/day_summary_panel.dart)) filled
with `??=` and keyed by `l10n.localeName`, so a locale change still gets a
correct instance and everything else gets the cached one.

## 5. `allEvents` passes through without a second wrap

`_onCreateEvent`, `_onUpdateEvent` and `_onDeleteEvent` emitted
`allEvents: List.unmodifiable(service.events)` — an O(n) copy per mutation of
a list that `CalendarEventService` already rebuilds as a fresh
`List.unmodifiable` on every mutation. They now pass `service.events`
straight through. The pass-through is sound **only because** every mutation
path really does reassign `_cache` to a new identity — the property
`sameGridInputs`, the `_visibleEvents` memo and `_partitionFor` all lean on
via `identical()` — so
[calendar_bloc_allevents_identity_test.dart](../test/bloc/calendar_bloc_allevents_identity_test.dart)
pins it: same identity as the service after each mutation, new identity
across mutations. A future service that mutates its cache in place fails
there, not as a silently stale grid.
