import 'package:equatable/equatable.dart';

import '../constants/category_kinds.dart';

/// The goal the owner set on a category's primary measure (record §6.6):
/// [value] in the primary's unit (occurrences, days, minutes, tasks, cents),
/// per [period] — absent for [TargetKind.maxGap], whose [value] is the most
/// days allowed between two occurrences.
final class ReportTarget extends Equatable {
  final TargetKind kind;
  final int value;
  final TargetPeriod? period;

  const ReportTarget({required this.kind, required this.value, this.period})
    : assert(value >= 1),
      assert((kind == TargetKind.maxGap) == (period == null));

  /// The target's three flat columns, spread into the profile's row.
  Map<String, dynamic> toJson() => {
    CategoryProfileKeys.targetKind: kind.name,
    CategoryProfileKeys.targetValue: value,
    CategoryProfileKeys.targetPeriod: period?.name,
  };

  /// The target in a profile row, or null when the row holds none it can
  /// use: an unknown kind, a missing value, or a missing period on a kind
  /// that needs one. A value below 1 is read as 1, and a period on a gap is
  /// ignored.
  static ReportTarget? fromJson(Map<String, dynamic> map) {
    final rawKind = map[CategoryProfileKeys.targetKind];
    final kind = TargetKind.parse(rawKind is String ? rawKind : null);
    final value = map[CategoryProfileKeys.targetValue];
    if (kind == null || value is! int) return null;
    final clamped = value < 1 ? 1 : value;
    if (kind == TargetKind.maxGap) {
      return ReportTarget(kind: kind, value: clamped);
    }
    final rawPeriod = map[CategoryProfileKeys.targetPeriod];
    final period = TargetPeriod.parse(rawPeriod is String ? rawPeriod : null);
    if (period == null) return null;
    return ReportTarget(kind: kind, value: clamped, period: period);
  }

  @override
  List<Object?> get props => [kind, value, period];
}

/// One category's stored analytics profile (record §9): its [kind] and only
/// what the owner overrode. Every override is nullable, null meaning "the
/// kind's own"; [effective] lays them over the kind's row.
///
/// A category without a profile resolves exactly as a [CategoryKind.custom]
/// profile with nothing overridden ([EffectiveProfile.unprofiled]) — today's
/// report, so an unprofiled calendar changes nothing.
class CategoryProfile extends Equatable {
  final String id;
  final String categoryId;
  final CategoryKind kind;
  final LifeArea? area;

  /// Overrides the kind's primary measure.
  final ReportMeasure? measure;

  /// The "counts as" duration the owner confirmed (I); null = untimed
  /// occurrences earn no hours. Never the kind's suggestion.
  final int? nominalMinutes;

  /// Null = the kind's verb; `''` = this category does not mark; any other
  /// text = the owner's own word for a kept mark.
  final String? markVerb;

  final bool? marksNew;
  final bool? assumeAbsentNew;
  final bool? countsHours;
  final ReportTarget? target;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CategoryProfile({
    required this.id,
    required this.categoryId,
    this.kind = CategoryKind.custom,
    this.area,
    this.measure,
    this.nominalMinutes,
    this.markVerb,
    this.marksNew,
    this.assumeAbsentNew,
    this.countsHours,
    this.target,
    this.createdAt,
    this.updatedAt,
  }) : assert(nominalMinutes == null || nominalMinutes > 0);

  /// Whether any field beyond the kind is the owner's own.
  bool get hasOverrides =>
      area != null ||
      measure != null ||
      nominalMinutes != null ||
      markVerb != null ||
      marksNew != null ||
      assumeAbsentNew != null ||
      countsHours != null ||
      target != null;

  /// This profile resolved; see [effectiveOf].
  EffectiveProfile get effective => effectiveOf(this);

  /// The kind's row under [profile]'s overrides — the one resolution the
  /// editor, the report builder, the detail sheet's verb and the digest all
  /// read (record §8). Null is [EffectiveProfile.unprofiled].
  ///
  /// A mark verb of `''` turns marking off, and a category that does not
  /// mark never pre-fills presence on a new event, whatever [marksNew] or
  /// [assumeAbsentNew] says — an absence nobody can mark kept would count
  /// against it for good.
  /// The kind's fallback measure stays only while the kind's own primary
  /// leads: it answers that measure's missing source, not another's.
  static EffectiveProfile effectiveOf(CategoryProfile? profile) {
    if (profile == null) return EffectiveProfile.unprofiled;
    final row = CategoryKinds.of(profile.kind);
    final verbOverride = profile.markVerb;
    final marks = verbOverride == null
        ? row.verb != null
        : verbOverride.isNotEmpty;
    final primary = profile.measure ?? row.primary;
    return EffectiveProfile(
      kind: row.kind,
      area: profile.area ?? row.area,
      primary: primary,
      primaryFallback: primary == row.primary ? row.primaryFallback : null,
      secondary: row.secondary,
      marks: marks,
      verb: marks ? row.verb : null,
      customVerb: verbOverride != null && verbOverride.isNotEmpty
          ? verbOverride
          : null,
      marksNew: marks && (profile.marksNew ?? row.marksNew),
      assumeAbsentNew:
          marks && (profile.assumeAbsentNew ?? row.assumeAbsentNew),
      countsHours: profile.countsHours ?? row.countsHours,
      nominalMinutes: profile.nominalMinutes,
      suggestedMinutes: row.suggestedMinutes,
      target: profile.target,
      targetPresets: row.targets,
    );
  }

  CategoryProfile copyWith({
    String? id,
    String? categoryId,
    CategoryKind? kind,
    LifeArea? area,
    ReportMeasure? measure,
    int? nominalMinutes,
    String? markVerb,
    bool? marksNew,
    bool? assumeAbsentNew,
    bool? countsHours,
    ReportTarget? target,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearArea = false,
    bool clearMeasure = false,
    bool clearNominalMinutes = false,
    bool clearMarkVerb = false,
    bool clearMarksNew = false,
    bool clearAssumeAbsentNew = false,
    bool clearCountsHours = false,
    bool clearTarget = false,
  }) {
    return CategoryProfile(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      kind: kind ?? this.kind,
      area: clearArea ? null : (area ?? this.area),
      measure: clearMeasure ? null : (measure ?? this.measure),
      nominalMinutes: clearNominalMinutes
          ? null
          : (nominalMinutes ?? this.nominalMinutes),
      markVerb: clearMarkVerb ? null : (markVerb ?? this.markVerb),
      marksNew: clearMarksNew ? null : (marksNew ?? this.marksNew),
      assumeAbsentNew: clearAssumeAbsentNew
          ? null
          : (assumeAbsentNew ?? this.assumeAbsentNew),
      countsHours: clearCountsHours ? null : (countsHours ?? this.countsHours),
      target: clearTarget ? null : (target ?? this.target),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    CategoryProfileKeys.id: id,
    CategoryProfileKeys.categoryId: categoryId,
    CategoryProfileKeys.kind: kind.name,
    CategoryProfileKeys.area: area?.name,
    CategoryProfileKeys.measure: measure?.name,
    CategoryProfileKeys.nominalMinutes: nominalMinutes,
    CategoryProfileKeys.markVerb: markVerb,
    CategoryProfileKeys.marksNew: marksNew,
    CategoryProfileKeys.assumeAbsentNew: assumeAbsentNew,
    CategoryProfileKeys.countsHours: countsHours,
    ...(target?.toJson() ??
        const {
          CategoryProfileKeys.targetKind: null,
          CategoryProfileKeys.targetValue: null,
          CategoryProfileKeys.targetPeriod: null,
        }),
    CategoryProfileKeys.createdAt: createdAt?.millisecondsSinceEpoch,
    CategoryProfileKeys.updatedAt: updatedAt?.millisecondsSinceEpoch,
  };

  /// Decodes one profile, or `null` when the map carries no usable identity
  /// — `CategoryAlert.fromJson`'s rule: every other field falls back rather
  /// than rejecting the row. An unknown kind is [CategoryKind.custom], an
  /// override this build cannot read is absent, a counts-as below one
  /// minute is none.
  static CategoryProfile? fromJson(Map<String, dynamic> map) {
    final id = map[CategoryProfileKeys.id];
    final categoryId = map[CategoryProfileKeys.categoryId];
    if (id is! String || id.isEmpty) return null;
    if (categoryId is! String || categoryId.isEmpty) return null;
    final nominal = map[CategoryProfileKeys.nominalMinutes];
    return CategoryProfile(
      id: id,
      categoryId: categoryId,
      kind:
          CategoryKind.parse(_string(map[CategoryProfileKeys.kind])) ??
          CategoryKind.custom,
      area: LifeArea.parse(_string(map[CategoryProfileKeys.area])),
      measure: ReportMeasure.parse(_string(map[CategoryProfileKeys.measure])),
      nominalMinutes: nominal is int && nominal > 0 ? nominal : null,
      markVerb: _string(map[CategoryProfileKeys.markVerb]),
      marksNew: _bool(map[CategoryProfileKeys.marksNew]),
      assumeAbsentNew: _bool(map[CategoryProfileKeys.assumeAbsentNew]),
      countsHours: _bool(map[CategoryProfileKeys.countsHours]),
      target: ReportTarget.fromJson(map),
      createdAt: _date(map[CategoryProfileKeys.createdAt]),
      updatedAt: _date(map[CategoryProfileKeys.updatedAt]),
    );
  }

  static String? _string(Object? raw) => raw is String ? raw : null;

  static bool? _bool(Object? raw) => raw is bool ? raw : null;

  /// Local time, as Drift reads the row back: `DateTime ==` compares the zone
  /// too, so a UTC decode never equaled the stored profile it came from.
  static DateTime? _date(Object? raw) =>
      raw is int ? DateTime.fromMillisecondsSinceEpoch(raw) : null;

  @override
  List<Object?> get props => [
    id,
    categoryId,
    kind,
    area,
    measure,
    nominalMinutes,
    markVerb,
    marksNew,
    assumeAbsentNew,
    countsHours,
    target,
    createdAt,
    updatedAt,
  ];
}

/// A category's kind row under its profile's overrides — what every reader
/// acts on, never the stored [CategoryProfile] itself.
final class EffectiveProfile extends Equatable {
  final CategoryKind kind;
  final LifeArea area;

  /// Null is Auto: the builder picks the measure over the span's events.
  final ReportMeasure? primary;
  final ReportMeasure? primaryFallback;
  final List<ReportMeasure> secondary;

  /// Whether occurrences in the category are marked at all: a verb resolves,
  /// the kind's or the owner's.
  final bool marks;

  /// The kind's verb while [marks] holds; drawn when [customVerb] is null.
  final MarkVerb? verb;

  /// The owner's own word for a kept mark, which outranks [verb].
  final String? customVerb;

  final bool marksNew;
  final bool assumeAbsentNew;
  final bool countsHours;

  /// The confirmed counts-as only; [suggestedMinutes] is a hint and never
  /// reaches a total.
  final int? nominalMinutes;
  final int? suggestedMinutes;
  final ReportTarget? target;
  final List<TargetPreset> targetPresets;

  const EffectiveProfile({
    required this.kind,
    required this.area,
    required this.primary,
    required this.primaryFallback,
    required this.secondary,
    required this.marks,
    required this.verb,
    required this.customVerb,
    required this.marksNew,
    required this.assumeAbsentNew,
    required this.countsHours,
    required this.nominalMinutes,
    required this.suggestedMinutes,
    required this.target,
    required this.targetPresets,
  });

  /// A category with no profile: [CategoryKind.custom]'s row with nothing
  /// overridden, which renders exactly today's report. The values repeat
  /// that row's because a const cannot read another const's fields; a test
  /// pins the two equal.
  static const EffectiveProfile unprofiled = EffectiveProfile(
    kind: CategoryKind.custom,
    area: LifeArea.other,
    primary: null,
    primaryFallback: null,
    secondary: [],
    marks: false,
    verb: null,
    customVerb: null,
    marksNew: false,
    assumeAbsentNew: false,
    countsHours: true,
    nominalMinutes: null,
    suggestedMinutes: null,
    target: null,
    targetPresets: [
      TargetPreset(TargetKind.atLeast, TargetPeriod.week),
      TargetPreset(TargetKind.atMost, TargetPeriod.week),
      TargetPreset(TargetKind.maxGap),
      TargetPreset(TargetKind.budget, TargetPeriod.month),
    ],
  );

  /// Whether this resolves as a category with no profile — today's
  /// behaviour, so a reader can take its old path unchanged.
  bool get isUnprofiled => this == unprofiled;

  @override
  List<Object?> get props => [
    kind,
    area,
    primary,
    primaryFallback,
    secondary,
    marks,
    verb,
    customVerb,
    marksNew,
    assumeAbsentNew,
    countsHours,
    nominalMinutes,
    suggestedMinutes,
    target,
    targetPresets,
  ];
}
