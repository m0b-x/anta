import '../constants/occurrence_descriptions.dart';
import '../models/calendar_event.dart';
import '../services/folder_search_service.dart' show normalizeForSearch;
import 'event_search_query.dart';

/// The agenda's search grammar, applied to one event and then to one of its
/// days.
///
/// Extracted from `EventAgenda.occurrencesInRange` so the scan and a
/// post-filter over entries already resolved speak **one grammar**: the same
/// fold caches, the same order of folds, the same per-day override rule. The
/// scan asks [mayMatch] once per event before the day loop and [matches] per
/// (event, day) inside it; a caller filtering cached entries asks [matches]
/// alone.
///
/// What an event satisfies is decided once and memoized on the event's
/// identity — an edited event is a new object and resolves afresh. The memo
/// also reads [OccurrenceDescriptions], so a matcher lives as long as its
/// query and the descriptions it saw: build a new one when either changes.
class EventQueryMatcher {
  final EventSearchQuery query;
  final String Function(CalendarEvent event)? _labelTextOf;

  /// Folded once per category, never per event or per occurrence: the catalog
  /// is a handful of entries and the label is a property of the category, not
  /// of the events wearing it.
  final Map<String, int> _categoryMasks;

  /// `null` for an event the query has already ruled out.
  final Map<CalendarEvent, _EventQueryMatch?> _states =
      Map<CalendarEvent, _EventQueryMatch?>.identity();

  /// [categoryLabels] maps a category id to its localized label and
  /// [labelTextOf] supplies the rest of what a row shows (see
  /// `EventAgenda.occurrencesInRange`); both stay closures and maps so this
  /// file stays `AppLocalizations`-free.
  EventQueryMatcher({
    required this.query,
    Map<String, String> categoryLabels = const {},
    String Function(CalendarEvent event)? labelTextOf,
  }) : _labelTextOf = labelTextOf,
       _categoryMasks = _maskCategories(query, categoryLabels);

  static Map<String, int> _maskCategories(
    EventSearchQuery query,
    Map<String, String> categoryLabels,
  ) {
    final masks = <String, int>{};
    if (query.isEmpty) return masks;
    categoryLabels.forEach((id, label) {
      final mask = query.maskOf(label);
      if (mask != 0) masks[id] = mask;
    });
    return masks;
  }

  bool get searching => query.isNotEmpty;

  /// Whether [event] can match on **some** day — the scan's candidate test.
  /// False means no day of it ever matches, so the scan never expands it.
  bool mayMatch(CalendarEvent event) => !searching || _stateOf(event) != null;

  /// Whether [event] still matches the query **on this day**.
  ///
  /// Everything but the last line was decided once per event; only an event
  /// carrying per-occurrence text pays anything per day, and then only for
  /// the days it actually overrode. A live override wins over the template
  /// **including when its text is empty**, which is what preserves the
  /// documented asymmetry: a day whose override no longer mentions the needle
  /// drops out of *that day* even though the template still matches, and
  /// symmetrically an override on one day cannot drag the event's every other
  /// occurrence into the results.
  bool matches(CalendarEvent event, DateTime day) {
    if (!searching) return true;
    final state = _stateOf(event);
    if (state == null) return false;
    if (state.always) return true;
    // Both halves were decided once per event — the labels no more vary by
    // day than the title does.
    var mask = state.base | state.labels;
    if (state.varies) {
      final override = OccurrenceDescriptions.overrideFor(event.id, day);
      mask |= override == null
          ? state.template
          : _descriptionFoldMask(override, query);
    } else {
      mask |= state.template;
    }
    return query.satisfied(mask, day);
  }

  _EventQueryMatch? _stateOf(CalendarEvent event) {
    if (_states.containsKey(event)) return _states[event];
    return _states[event] = _resolve(event);
  }

  /// What [event] already satisfies, decided once per event instead of once
  /// per (event, day) — **4.1**. Only an event carrying per-day text, or a
  /// query carrying a date term, pays anything per day.
  _EventQueryMatch? _resolve(CalendarEvent event) {
    final base =
        query.maskOf(event.title) | (_categoryMasks[event.categoryId] ?? 0);
    // Everything the title and the category already answer for is settled;
    // nothing below is folded for what they already closed, so a title hit
    // still costs neither a label nor a description fold.
    final baseSettles = query.couldSatisfy(base);
    // The row's own labels come **before** the description: they are short,
    // already on screen, and settling here spares a whole-description fold.
    // A template that still matches is folded either way, so every
    // description-fold budget the scan is pinned to stays where it was.
    final labelTextOf = _labelTextOf;
    var labels = 0;
    if (!baseSettles && labelTextOf != null) {
      labels = _labelFoldMask(event, labelTextOf(event), query);
    }
    final settled = base | labels;
    final settledSatisfies = labels == 0
        ? baseSettles
        : query.couldSatisfy(settled);
    var template = 0;
    if (!settledSatisfies) {
      final description = event.description;
      if (description != null) {
        template = _templateFoldMask(event, description, query);
      }
    }
    // Cheap existence probe — the per-day pass decides which days actually
    // match. Without it, an event whose only hit is a single day's override
    // never reaches the scan.
    final varies =
        !settledSatisfies &&
        OccurrenceDescriptions.appliesTo(event) &&
        OccurrenceDescriptions.hasAnyOverride(event.id);
    // Deliberately a *superset* test: with per-occurrence descriptions an
    // event may match only through text living on one specific day, so
    // dropping it here would make that text unfindable. A date term is
    // likewise treated as satisfiable here and narrowed per day.
    if (!settledSatisfies &&
        !varies &&
        !query.couldSatisfy(settled | template)) {
      return null;
    }
    return _EventQueryMatch(
      base: base,
      labels: labels,
      template: template,
      varies: varies,
      always: !query.hasDateClauses && (settledSatisfies || !varies),
    );
  }

  /// Counts description folds performed by the matcher — the work **4.1**
  /// exists to bound. Incremented inside an `assert`, so both the statement
  /// and its closure are stripped from profile and release builds and cost
  /// nothing there, mirroring `CalendarEvent.debugOccursOnCalls`.
  ///
  /// A fold copies a whole description (up to the settings-capped ceiling)
  /// through the shared search normalization, and a top-level function has no
  /// injection seam, so this is what lets a test assert that the scan folds a
  /// template **once per event** rather than once per (event, day). Title
  /// folds are deliberately not counted: those were already once per event
  /// before 4.1. Tests read it through `EventAgenda.debugDescriptionFolds`,
  /// the scan's own name, which is why this one is not `@visibleForTesting`.
  static int debugDescriptionFolds = 0;

  /// Counts calls to the `labelTextOf` closure's fold. Mirrors
  /// [debugDescriptionFolds] exactly, `assert`-only so it costs nothing in
  /// profile and release builds.
  ///
  /// The closure builds several localized strings — a recurrence phrase, a
  /// formatted time range — so the property worth pinning is that it runs
  /// **once per candidate event**, never once per (event, day), and not at all
  /// when the title or the category already settled the query. Tests read it
  /// through `EventAgenda.debugLabelFolds`.
  static int debugLabelFolds = 0;

  /// Drops every cached fold. For tests that count folds across scans, called
  /// through `EventAgenda.debugClearFoldCaches`.
  static void debugClearFoldCaches() {
    _foldCacheGeneration++;
  }

  static int _foldCacheGeneration = 0;

  /// Folds [text] into [query]'s term bits, counting the fold. The one place a
  /// description is normalized during a scan, so [debugDescriptionFolds]
  /// cannot drift from what actually happens.
  static int _descriptionFoldMask(String text, EventSearchQuery query) {
    assert(() {
      debugDescriptionFolds++;
      return true;
    }());
    return query.maskOf(text);
  }

  /// Per-event folds that survive across scans: the normalized template
  /// description and the normalized row labels, keyed on the event's
  /// identity and on the identity of the string they were folded from. A
  /// keystroke pause then costs one `contains` per term per candidate rather
  /// than re-normalizing every description in the store; an edited event is a
  /// new object and misses on its own.
  static final Expando<_EventFolds> _folds = Expando<_EventFolds>();

  static _EventFolds _foldsOf(CalendarEvent event) {
    final cached = _folds[event];
    if (cached != null && cached.generation == _foldCacheGeneration) {
      return cached;
    }
    return _folds[event] = _EventFolds();
  }

  /// [_descriptionFoldMask] for the event's own template, folded once per
  /// event object rather than once per scan.
  static int _templateFoldMask(
    CalendarEvent event,
    String description,
    EventSearchQuery query,
  ) {
    final folds = _foldsOf(event);
    var folded = folds.templateFold;
    if (folded == null || !identical(folds.templateSource, description)) {
      assert(() {
        debugDescriptionFolds++;
        return true;
      }());
      folded = normalizeForSearch(description);
      folds.templateSource = description;
      folds.templateFold = folded;
    }
    return query.maskOfFolded(folded);
  }

  /// Folds [text] into [query]'s term bits, counting the fold. The one place a
  /// row's display labels are normalized during a scan, so [debugLabelFolds]
  /// cannot drift from what actually happens. Cached per event on the
  /// identity of [text]: `AgendaSearchText.forEventCached` hands back the same
  /// string for the same event and locale, so the fold is paid once.
  static int _labelFoldMask(
    CalendarEvent event,
    String text,
    EventSearchQuery query,
  ) {
    final folds = _foldsOf(event);
    var folded = folds.labelFold;
    if (folded == null || !identical(folds.labelSource, text)) {
      assert(() {
        debugLabelFolds++;
        return true;
      }());
      folded = normalizeForSearch(text);
      folds.labelSource = text;
      folds.labelFold = folded;
    }
    return query.maskOfFolded(folded);
  }
}

/// An event's cached folds — see `EventQueryMatcher._folds`. Invalidated as a
/// whole by `debugClearFoldCaches` through the generation stamp.
class _EventFolds {
  final int generation = EventQueryMatcher._foldCacheGeneration;
  String? templateSource;
  String? templateFold;
  String? labelSource;
  String? labelFold;
}

/// What a candidate event already satisfies of the active query, resolved once
/// per event by [EventQueryMatcher.mayMatch].
///
/// [base] holds the term bits the title and the category label answer for —
/// neither varies by day. [labels] holds the bits the row's own rendered
/// labels answer for (recurrence pattern, time or "All day", priority word),
/// folded once for what [base] left open and just as day-invariant.
/// [template] holds the template description's bits, folded only for what the
/// two above left open. [varies] means the day loop has to ask
/// [OccurrenceDescriptions] whether this day overrode that template, and a
/// live override **replaces** [template] rather than adding to it, including
/// when its text is empty. [always] short-circuits the whole thing for the
/// common case: no date term to narrow by, and nothing left for a day to
/// change.
class _EventQueryMatch {
  final int base;
  final int labels;
  final int template;
  final bool varies;
  final bool always;

  const _EventQueryMatch({
    required this.base,
    required this.labels,
    required this.template,
    required this.varies,
    required this.always,
  });
}
