import 'package:equatable/equatable.dart';

import '../constants/json_keys.dart';

/// Operation a [CounterBinding] performs each time its token is expanded.
enum CounterOp {
  increment,
  keep,
  decrement;

  String toJson() => name;

  static CounterOp fromJson(Object? value) {
    if (value is String) {
      for (final op in CounterOp.values) {
        if (op.name == value) return op;
      }
    }
    return CounterOp.increment;
  }
}

/// Binds a counter to a shortcut so its value can be expanded via the
/// `{c1}` / `{c2}` tokens in [CustomMarkdownShortcut.beforeText] /
/// [CustomMarkdownShortcut.afterText].
///
/// Each occurrence of the matching token triggers exactly one operation
/// (increment, keep, or decrement) and substitutes the resulting value.
class CounterBinding extends Equatable {
  final String counterId;
  final CounterOp op;

  const CounterBinding({
    required this.counterId,
    this.op = CounterOp.increment,
  });

  Map<String, dynamic> toJson() => {
    JsonKeys.counterId: counterId,
    JsonKeys.counterOp: op.toJson(),
  };

  factory CounterBinding.fromJson(Map<String, dynamic> json) {
    return CounterBinding(
      counterId: json[JsonKeys.counterId] as String,
      op: CounterOp.fromJson(json[JsonKeys.counterOp]),
    );
  }

  CounterBinding copyWith({String? counterId, CounterOp? op}) {
    return CounterBinding(
      counterId: counterId ?? this.counterId,
      op: op ?? this.op,
    );
  }

  @override
  List<Object?> get props => [counterId, op];
}

/// Represents a date offset configuration for shortcuts
class DateOffset extends Equatable {
  final int days;
  final int months;
  final int years;

  const DateOffset({this.days = 0, this.months = 0, this.years = 0});

  bool get isEmpty => days == 0 && months == 0 && years == 0;

  Map<String, dynamic> toJson() => {
    JsonKeys.days: days,
    JsonKeys.months: months,
    JsonKeys.years: years,
  };

  factory DateOffset.fromJson(Map<String, dynamic> json) {
    return DateOffset(
      days: json[JsonKeys.days] as int? ?? 0,
      months: json[JsonKeys.months] as int? ?? 0,
      years: json[JsonKeys.years] as int? ?? 0,
    );
  }

  DateOffset copyWith({int? days, int? months, int? years}) {
    return DateOffset(
      days: days ?? this.days,
      months: months ?? this.months,
      years: years ?? this.years,
    );
  }

  @override
  List<Object?> get props => [days, months, years];
}

/// Configuration for repeating the shortcut multiple times
class RepeatConfig extends Equatable {
  final int count;
  final bool incrementDate;
  final int dateIncrementDays;
  final int dateIncrementMonths;
  final int dateIncrementYears;
  final String separator;

  /// Text to insert before all repeated items
  final String beforeRepeatText;

  /// Text to insert after all repeated items
  final String afterRepeatText;

  const RepeatConfig({
    this.count = 1,
    this.incrementDate = false,
    this.dateIncrementDays = 1,
    this.dateIncrementMonths = 0,
    this.dateIncrementYears = 0,
    this.separator = '\n',
    this.beforeRepeatText = '',
    this.afterRepeatText = '',
  });

  bool get isActive => count > 1;

  Map<String, dynamic> toJson() => {
    JsonKeys.repeatCount: count,
    JsonKeys.incrementDate: incrementDate,
    JsonKeys.dateIncrementDays: dateIncrementDays,
    JsonKeys.dateIncrementMonths: dateIncrementMonths,
    JsonKeys.dateIncrementYears: dateIncrementYears,
    JsonKeys.repeatSeparator: separator,
    JsonKeys.beforeRepeatText: beforeRepeatText,
    JsonKeys.afterRepeatText: afterRepeatText,
  };

  factory RepeatConfig.fromJson(Map<String, dynamic> json) {
    return RepeatConfig(
      count: json[JsonKeys.repeatCount] as int? ?? 1,
      incrementDate: json[JsonKeys.incrementDate] as bool? ?? false,
      dateIncrementDays: json[JsonKeys.dateIncrementDays] as int? ?? 1,
      dateIncrementMonths: json[JsonKeys.dateIncrementMonths] as int? ?? 0,
      dateIncrementYears: json[JsonKeys.dateIncrementYears] as int? ?? 0,
      separator: json[JsonKeys.repeatSeparator] as String? ?? '\n',
      beforeRepeatText: json[JsonKeys.beforeRepeatText] as String? ?? '',
      afterRepeatText: json[JsonKeys.afterRepeatText] as String? ?? '',
    );
  }

  RepeatConfig copyWith({
    int? count,
    bool? incrementDate,
    int? dateIncrementDays,
    int? dateIncrementMonths,
    int? dateIncrementYears,
    String? separator,
    String? beforeRepeatText,
    String? afterRepeatText,
  }) {
    return RepeatConfig(
      count: count ?? this.count,
      incrementDate: incrementDate ?? this.incrementDate,
      dateIncrementDays: dateIncrementDays ?? this.dateIncrementDays,
      dateIncrementMonths: dateIncrementMonths ?? this.dateIncrementMonths,
      dateIncrementYears: dateIncrementYears ?? this.dateIncrementYears,
      separator: separator ?? this.separator,
      beforeRepeatText: beforeRepeatText ?? this.beforeRepeatText,
      afterRepeatText: afterRepeatText ?? this.afterRepeatText,
    );
  }

  @override
  List<Object?> get props => [
    count,
    incrementDate,
    dateIncrementDays,
    dateIncrementMonths,
    dateIncrementYears,
    separator,
    beforeRepeatText,
    afterRepeatText,
  ];
}

class CustomMarkdownShortcut extends Equatable {
  final String id;
  final String label;
  final int iconCodePoint;
  final String iconFontFamily;
  final String beforeText;
  final String afterText;
  final bool isDefault;
  final bool isVisible;
  final String insertType;
  final String? dateFormat;
  final DateOffset? dateOffset;
  final RepeatConfig? repeatConfig;
  final String? counterId;

  /// Free-text grouping label used to filter the shortcut list in settings.
  ///
  /// Purely organisational metadata: it never affects toolbar order or
  /// rendering. `null` or empty means uncategorised.
  final String? category;

  /// Counter bindings used by the `{c1}` / `{c2}` tokens in
  /// [beforeText] / [afterText] / repeat wrapper text.
  ///
  /// `counters[0]` corresponds to `{c1}`, `counters[1]` to `{c2}`. Up to
  /// two bindings are supported. Each binding can independently increment
  /// or decrement its counter.
  ///
  /// For backward compatibility, when this list is empty but [counterId]
  /// is non-null (legacy single-counter shortcuts), [effectiveCounters]
  /// synthesises a single increment binding so applier logic can rely on
  /// the new field uniformly.
  final List<CounterBinding> counters;

  const CustomMarkdownShortcut({
    required this.id,
    required this.label,
    required this.iconCodePoint,
    required this.iconFontFamily,
    required this.beforeText,
    required this.afterText,
    this.isDefault = false,
    this.isVisible = true,
    this.insertType = 'wrap',
    this.dateFormat,
    this.dateOffset,
    this.repeatConfig,
    this.counterId,
    this.category,
    this.counters = const [],
  });

  /// Returns the effective counter binding list, synthesising one from
  /// [counterId] when the new [counters] field is empty (legacy data).
  List<CounterBinding> get effectiveCounters {
    if (counters.isNotEmpty) return counters;
    final legacy = counterId;
    if (legacy != null && legacy.isNotEmpty) {
      return [CounterBinding(counterId: legacy)];
    }
    return const [];
  }

  Map<String, dynamic> toJson() {
    return {
      JsonKeys.id: id,
      JsonKeys.label: label,
      JsonKeys.iconCodePoint: iconCodePoint,
      JsonKeys.iconFontFamily: iconFontFamily,
      JsonKeys.beforeText: beforeText,
      JsonKeys.afterText: afterText,
      JsonKeys.isDefault: isDefault,
      JsonKeys.isVisible: isVisible,
      JsonKeys.insertType: insertType,
      if (dateFormat != null) JsonKeys.dateFormat: dateFormat,
      if (dateOffset != null) JsonKeys.dateOffset: dateOffset!.toJson(),
      if (repeatConfig != null) JsonKeys.repeatConfig: repeatConfig!.toJson(),
      if (counterId != null) JsonKeys.counterId: counterId,
      if (category != null && category!.isNotEmpty) JsonKeys.category: category,
      if (counters.isNotEmpty)
        JsonKeys.counters: counters.map((c) => c.toJson()).toList(),
    };
  }

  factory CustomMarkdownShortcut.fromJson(Map<String, dynamic> json) {
    return CustomMarkdownShortcut(
      id: json[JsonKeys.id] as String,
      label: json[JsonKeys.label] as String,
      iconCodePoint: json[JsonKeys.iconCodePoint] as int,
      iconFontFamily: json[JsonKeys.iconFontFamily] as String,
      beforeText: json[JsonKeys.beforeText] as String,
      afterText: json[JsonKeys.afterText] as String,
      isDefault: json[JsonKeys.isDefault] as bool? ?? false,
      isVisible: json[JsonKeys.isVisible] as bool? ?? true,
      insertType: json[JsonKeys.insertType] as String? ?? 'wrap',
      dateFormat: json[JsonKeys.dateFormat] as String?,
      dateOffset: json[JsonKeys.dateOffset] != null
          ? DateOffset.fromJson(
              json[JsonKeys.dateOffset] as Map<String, dynamic>,
            )
          : null,
      repeatConfig: json[JsonKeys.repeatConfig] != null
          ? RepeatConfig.fromJson(
              json[JsonKeys.repeatConfig] as Map<String, dynamic>,
            )
          : null,
      counterId: json[JsonKeys.counterId] as String?,
      category: json[JsonKeys.category] as String?,
      counters:
          (json[JsonKeys.counters] as List?)
              ?.map((e) => CounterBinding.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  CustomMarkdownShortcut copyWith({
    String? id,
    String? label,
    int? iconCodePoint,
    String? iconFontFamily,
    String? beforeText,
    String? afterText,
    bool? isDefault,
    bool? isVisible,
    String? insertType,
    String? dateFormat,
    DateOffset? dateOffset,
    RepeatConfig? repeatConfig,
    String? counterId,
    String? category,
    bool clearDateOffset = false,
    bool clearRepeatConfig = false,
    bool clearCounterId = false,
    bool clearCategory = false,
    List<CounterBinding>? counters,
  }) {
    return CustomMarkdownShortcut(
      id: id ?? this.id,
      label: label ?? this.label,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      iconFontFamily: iconFontFamily ?? this.iconFontFamily,
      beforeText: beforeText ?? this.beforeText,
      afterText: afterText ?? this.afterText,
      isDefault: isDefault ?? this.isDefault,
      isVisible: isVisible ?? this.isVisible,
      insertType: insertType ?? this.insertType,
      dateFormat: dateFormat ?? this.dateFormat,
      dateOffset: clearDateOffset ? null : (dateOffset ?? this.dateOffset),
      repeatConfig: clearRepeatConfig
          ? null
          : (repeatConfig ?? this.repeatConfig),
      counterId: clearCounterId ? null : (counterId ?? this.counterId),
      category: clearCategory ? null : (category ?? this.category),
      counters: counters ?? this.counters,
    );
  }

  @override
  List<Object?> get props => [
    id,
    label,
    iconCodePoint,
    iconFontFamily,
    beforeText,
    afterText,
    isDefault,
    isVisible,
    insertType,
    dateFormat,
    dateOffset,
    repeatConfig,
    counterId,
    category,
    counters,
  ];
}
