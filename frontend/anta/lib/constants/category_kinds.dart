import 'package:equatable/equatable.dart';

/// What a calendar category is for (`docs/calendar-analytics-roadmap.md`
/// D, §6.2): the preset that decides what the Report measures for it, which
/// verb its mark uses, whether new events track presence and which goal it
/// offers.
///
/// Persisted by [name] — the profile's `kind` column and its backup key — so
/// a value is never renamed; a new kind is appended before [custom] in the
/// catalogue and parses as [custom] on an older build.
enum CategoryKind {
  routine,
  workout,
  medication,
  sleep,
  episode,
  appointment,
  work,
  meeting,
  task,
  deadline,
  study,
  bill,
  income,
  social,
  anniversary,
  chore,
  maintenance,
  expiry,
  trip,
  leave,
  custom;

  /// The kind stored as [key], or null for a key this build does not know;
  /// the profile's decoder reads null as [custom].
  static CategoryKind? parse(String? key) {
    for (final kind in values) {
      if (kind.name == key) return kind;
    }
    return null;
  }
}

/// The life area a kind belongs to by default (M): Balance sums hours per
/// area, and the kind picker groups its rows by it. Persisted by [name].
enum LifeArea {
  health,
  work,
  money,
  people,
  home,
  leisure,
  other;

  /// The area stored as [key], or null for a key this build does not know —
  /// the profile then falls back to its kind's area.
  static LifeArea? parse(String? key) {
    for (final area in values) {
      if (area.name == key) return area;
    }
    return null;
  }
}

/// The word a kept mark is read as ("Paid", "Met"). Only the key lives here:
/// the words are localised where they are drawn.
enum MarkVerb {
  done,
  attended,
  taken,
  paid,
  received,
  met,
  renewed;

  /// The verb stored as [key], or null for a key this build does not know.
  static MarkVerb? parse(String? key) {
    for (final verb in values) {
      if (verb.name == key) return verb;
    }
    return null;
  }
}

/// One number a category yields over a span (record §6.3, H). Persisted by
/// [name] as the profile's primary override.
enum ReportMeasure {
  count,
  events,
  hours,
  attendance,
  cancelled,
  tasks,
  money,
  lastSeen,
  leadTime,
  timing,
  daysUntil;

  /// The measure stored as [key], or null for a key this build does not
  /// know — the override then reads as absent and the kind's primary leads.
  static ReportMeasure? parse(String? key) {
    for (final measure in values) {
      if (measure.name == key) return measure;
    }
    return null;
  }
}

/// The four target shapes (J). Persisted by [name].
enum TargetKind {
  atLeast,
  atMost,
  maxGap,
  budget;

  /// The kind stored as [key], or null for a key this build does not know.
  static TargetKind? parse(String? key) {
    for (final kind in values) {
      if (kind.name == key) return kind;
    }
    return null;
  }
}

/// The calendar period a target is counted over. Persisted by [name].
enum TargetPeriod {
  day,
  week,
  month,
  year;

  /// The period stored as [key], or null for a key this build does not know.
  static TargetPeriod? parse(String? key) {
    for (final period in values) {
      if (period.name == key) return period;
    }
    return null;
  }
}

/// A goal a kind suggests first in the goal sheet: the target's shape, with
/// the value left to the owner. [period] is null exactly for
/// [TargetKind.maxGap], whose limit is a number of days rather than a count
/// per period.
///
/// Compared by value, so `EffectiveProfile` equality never rests on a preset
/// being the catalogue's canonical const.
final class TargetPreset extends Equatable {
  final TargetKind kind;
  final TargetPeriod? period;

  const TargetPreset(this.kind, [this.period])
    : assert((kind == TargetKind.maxGap) == (period == null));

  @override
  List<Object?> get props => [kind, period];
}

/// One kind's defaults. Every field but [kind] is overridable per category
/// in its `CategoryProfile`; `CategoryProfile.effectiveOf` lays the
/// overrides over this row.
final class CategoryKindRow {
  final CategoryKind kind;
  final LifeArea area;

  /// The measure that leads the category's header, meter, goal and digest
  /// word; null is Auto, resolved over the span's events by the builder.
  final ReportMeasure? primary;

  /// What [primary] falls back to when its source is absent over the span:
  /// a Task category with no task boxes counts occurrences, a Bill category
  /// with no linked note counts them too.
  final ReportMeasure? primaryFallback;

  final List<ReportMeasure> secondary;

  /// The kept mark's word; null when the kind does not mark at all.
  final MarkVerb? verb;

  /// Whether a new event in the category starts with presence tracking on —
  /// a pre-fill of the editor's switch, never a rewrite of an old event (U).
  final bool marksNew;

  /// Whether a new event starts with assume-absent on: an unmarked past day
  /// counts missed. Social is the one marking kind without it — an unmarked
  /// dinner happened.
  final bool assumeAbsentNew;

  /// Whether the category's hours count toward the Hours tile and Balance.
  final bool countsHours;

  /// The "counts as" hint for an untimed occurrence (I): shown, never
  /// applied until the owner confirms it.
  final int? suggestedMinutes;

  /// The goal presets the goal sheet offers first, in this order.
  final List<TargetPreset> targets;

  const CategoryKindRow({
    required this.kind,
    required this.area,
    this.primary,
    this.primaryFallback,
    this.secondary = const [],
    this.verb,
    this.marksNew = false,
    this.assumeAbsentNew = false,
    this.countsHours = false,
    this.suggestedMinutes,
    this.targets = const [],
  });
}

/// The kinds catalogue — the record's §6.2, one row per [CategoryKind] in
/// the enum's order, [CategoryKind.custom] last. A row never changes at
/// runtime: a category's own choices live in its profile's overrides.
abstract final class CategoryKinds {
  static const List<CategoryKindRow> all = [
    CategoryKindRow(
      kind: CategoryKind.routine,
      area: LifeArea.health,
      primary: ReportMeasure.attendance,
      secondary: [ReportMeasure.count],
      verb: MarkVerb.done,
      marksNew: true,
      assumeAbsentNew: true,
      countsHours: true,
      targets: [
        TargetPreset(TargetKind.atLeast, TargetPeriod.week),
        TargetPreset(TargetKind.maxGap),
      ],
    ),
    CategoryKindRow(
      kind: CategoryKind.workout,
      area: LifeArea.health,
      primary: ReportMeasure.attendance,
      secondary: [ReportMeasure.hours],
      verb: MarkVerb.attended,
      marksNew: true,
      assumeAbsentNew: true,
      countsHours: true,
      suggestedMinutes: 60,
      targets: [
        TargetPreset(TargetKind.atLeast, TargetPeriod.week),
        TargetPreset(TargetKind.maxGap),
      ],
    ),
    CategoryKindRow(
      kind: CategoryKind.medication,
      area: LifeArea.health,
      primary: ReportMeasure.attendance,
      verb: MarkVerb.taken,
      marksNew: true,
      assumeAbsentNew: true,
      targets: [TargetPreset(TargetKind.atLeast, TargetPeriod.week)],
    ),
    CategoryKindRow(
      kind: CategoryKind.sleep,
      area: LifeArea.health,
      primary: ReportMeasure.hours,
      secondary: [ReportMeasure.timing],
      targets: [TargetPreset(TargetKind.atLeast, TargetPeriod.day)],
    ),
    CategoryKindRow(
      kind: CategoryKind.episode,
      area: LifeArea.health,
      primary: ReportMeasure.count,
      secondary: [ReportMeasure.events, ReportMeasure.lastSeen],
    ),
    CategoryKindRow(
      kind: CategoryKind.appointment,
      area: LifeArea.health,
      primary: ReportMeasure.events,
      secondary: [ReportMeasure.lastSeen, ReportMeasure.hours],
      verb: MarkVerb.attended,
      marksNew: true,
      assumeAbsentNew: true,
      countsHours: true,
      suggestedMinutes: 60,
      targets: [TargetPreset(TargetKind.maxGap)],
    ),
    CategoryKindRow(
      kind: CategoryKind.work,
      area: LifeArea.work,
      primary: ReportMeasure.hours,
      secondary: [ReportMeasure.count],
      countsHours: true,
      suggestedMinutes: 480,
      targets: [TargetPreset(TargetKind.atMost, TargetPeriod.week)],
    ),
    CategoryKindRow(
      kind: CategoryKind.meeting,
      area: LifeArea.work,
      primary: ReportMeasure.hours,
      secondary: [ReportMeasure.count],
      countsHours: true,
      suggestedMinutes: 30,
      targets: [TargetPreset(TargetKind.atMost, TargetPeriod.week)],
    ),
    CategoryKindRow(
      kind: CategoryKind.task,
      area: LifeArea.work,
      primary: ReportMeasure.tasks,
      primaryFallback: ReportMeasure.count,
      verb: MarkVerb.done,
      marksNew: true,
      assumeAbsentNew: true,
      countsHours: true,
      suggestedMinutes: 30,
      targets: [TargetPreset(TargetKind.atLeast, TargetPeriod.week)],
    ),
    CategoryKindRow(
      kind: CategoryKind.deadline,
      area: LifeArea.work,
      primary: ReportMeasure.events,
      secondary: [ReportMeasure.leadTime],
      verb: MarkVerb.done,
      marksNew: true,
      assumeAbsentNew: true,
    ),
    CategoryKindRow(
      kind: CategoryKind.study,
      area: LifeArea.work,
      primary: ReportMeasure.hours,
      secondary: [ReportMeasure.attendance],
      verb: MarkVerb.attended,
      marksNew: true,
      assumeAbsentNew: true,
      countsHours: true,
      suggestedMinutes: 45,
      targets: [TargetPreset(TargetKind.atLeast, TargetPeriod.week)],
    ),
    CategoryKindRow(
      kind: CategoryKind.bill,
      area: LifeArea.money,
      primary: ReportMeasure.money,
      primaryFallback: ReportMeasure.count,
      verb: MarkVerb.paid,
      marksNew: true,
      assumeAbsentNew: true,
      targets: [TargetPreset(TargetKind.budget, TargetPeriod.month)],
    ),
    CategoryKindRow(
      kind: CategoryKind.income,
      area: LifeArea.money,
      primary: ReportMeasure.money,
      verb: MarkVerb.received,
      marksNew: true,
      assumeAbsentNew: true,
    ),
    CategoryKindRow(
      kind: CategoryKind.social,
      area: LifeArea.people,
      primary: ReportMeasure.events,
      secondary: [ReportMeasure.lastSeen, ReportMeasure.hours],
      verb: MarkVerb.met,
      marksNew: true,
      countsHours: true,
      suggestedMinutes: 120,
      targets: [
        TargetPreset(TargetKind.atLeast, TargetPeriod.month),
        TargetPreset(TargetKind.maxGap),
      ],
    ),
    CategoryKindRow(
      kind: CategoryKind.anniversary,
      area: LifeArea.people,
      primary: ReportMeasure.count,
    ),
    CategoryKindRow(
      kind: CategoryKind.chore,
      area: LifeArea.home,
      primary: ReportMeasure.count,
      secondary: [ReportMeasure.lastSeen],
      verb: MarkVerb.done,
      marksNew: true,
      assumeAbsentNew: true,
      countsHours: true,
      suggestedMinutes: 30,
      targets: [
        TargetPreset(TargetKind.atLeast, TargetPeriod.week),
        TargetPreset(TargetKind.maxGap),
      ],
    ),
    CategoryKindRow(
      kind: CategoryKind.maintenance,
      area: LifeArea.home,
      primary: ReportMeasure.lastSeen,
      secondary: [ReportMeasure.money],
      verb: MarkVerb.done,
      marksNew: true,
      assumeAbsentNew: true,
      targets: [TargetPreset(TargetKind.maxGap)],
    ),
    CategoryKindRow(
      kind: CategoryKind.expiry,
      area: LifeArea.home,
      primary: ReportMeasure.daysUntil,
      verb: MarkVerb.renewed,
      marksNew: true,
    ),
    CategoryKindRow(
      kind: CategoryKind.trip,
      area: LifeArea.leisure,
      primary: ReportMeasure.count,
      secondary: [ReportMeasure.events, ReportMeasure.money],
      targets: [TargetPreset(TargetKind.atLeast, TargetPeriod.year)],
    ),
    CategoryKindRow(
      kind: CategoryKind.leave,
      area: LifeArea.work,
      primary: ReportMeasure.count,
      targets: [TargetPreset(TargetKind.atMost, TargetPeriod.year)],
    ),
    // Today's calendar: the report counts every category's timed hours, and
    // the editor starts a new event with presence and assume-absent off.
    CategoryKindRow(
      kind: CategoryKind.custom,
      area: LifeArea.other,
      countsHours: true,
      targets: [
        TargetPreset(TargetKind.atLeast, TargetPeriod.week),
        TargetPreset(TargetKind.atMost, TargetPeriod.week),
        TargetPreset(TargetKind.maxGap),
        TargetPreset(TargetKind.budget, TargetPeriod.month),
      ],
    ),
  ];

  /// [kind]'s row. [all] follows the enum's order, so this is an index read.
  static CategoryKindRow of(CategoryKind kind) => all[kind.index];

  /// The picker's groups, in the enum's order.
  static List<LifeArea> get areas => LifeArea.values;

  /// The kinds whose default area is [area], in catalogue order.
  static List<CategoryKindRow> inArea(LifeArea area) => [
    for (final row in all)
      if (row.area == area) row,
  ];
}

/// The JSON keys one category profile round-trips through — the backup
/// archive's `categoryProfiles` rows. Flat and named after the table's
/// columns (record §9), so the backup row and the database row have one
/// shape.
abstract final class CategoryProfileKeys {
  static const String id = 'id';
  static const String categoryId = 'categoryId';
  static const String kind = 'kind';
  static const String area = 'area';
  static const String measure = 'measure';
  static const String nominalMinutes = 'nominalMinutes';
  static const String markVerb = 'markVerb';
  static const String marksNew = 'marksNew';
  static const String assumeAbsentNew = 'assumeAbsentNew';
  static const String countsHours = 'countsHours';
  static const String targetKind = 'targetKind';
  static const String targetValue = 'targetValue';
  static const String targetPeriod = 'targetPeriod';

  /// Epoch milliseconds under the sync binding's names, so an exported row
  /// is the row's wire map — the category alerts' `createdAtMs` precedent.
  static const String createdAt = 'createdAtMs';
  static const String updatedAt = 'updatedAtMs';
}
