import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';

/// Religious traditions the fasting engine can compute. Enabled per user in
/// Calendar Settings; disabled traditions cost nothing.
enum FastingTradition {
  orthodox,
  catholic,
  muslim,
  jewish;

  /// Forward-compatible parsing: unknown/null values yield null so callers
  /// can drop settings written by a newer version.
  static FastingTradition? fromName(String? name) {
    for (final tradition in values) {
      if (tradition.name == name) return tradition;
    }
    return null;
  }
}

/// How a tradition's fasting days render on the calendar grid. The day panel
/// always carries its fasting row; this only decides the grid's treatment.
enum FastingDisplayStyle {
  /// Faint wash behind the whole cell (default).
  tint,

  /// A bar in the day's marker strip, event-style.
  bar,

  /// The day number itself takes the colour and turns bold.
  strong,

  /// Grid untouched; fasting shows only in the day panel.
  none;

  /// Forward-compatible parsing: unknown/null values fall back to [tint].
  static FastingDisplayStyle fromName(String? name) {
    for (final style in values) {
      if (style.name == name) return style;
    }
    return tint;
  }
}

/// Where a tradition's row sits among the day panel's other entries (and
/// where its bar sits in the marker stack).
///
/// Exposed as placements rather than raw numbers because the underlying
/// scale is an implementation detail — `DaySummaryEntry` bands events at
/// 0..99, the public holiday at 150 and the weekend at 250, and asking a
/// user to pick "160" would leak all of that.
enum FastingRowPlacement {
  /// Above everything, events included.
  first(10),

  /// After events, before the public holiday.
  beforeHolidays(120),

  /// After the public holiday, before the weekend row (default).
  afterHolidays(160),

  /// Below everything.
  last(260);

  /// The `DaySummaryEntry.priority` / `DayBar.priority` this maps to.
  final int priority;

  const FastingRowPlacement(this.priority);

  /// Forward-compatible parsing: unknown/null values fall back to
  /// [afterHolidays].
  static FastingRowPlacement fromName(String? name) {
    for (final placement in values) {
      if (placement.name == name) return placement;
    }
    return afterHolidays;
  }
}

/// Per-tradition look & feel: grid style, colour, icon and row placement.
///
/// Every field is display-only — none of it can change *which* days are
/// fasting days, which is what lets the engine treat appearance edits as
/// free (no recomputation, no cache invalidation).
class FastingTraditionStyle extends Equatable {
  final FastingDisplayStyle style;

  /// Explicit ARGB colour, or null to follow the shared fasting violet.
  final int? colorValue;

  /// `CalendarIcons` key overriding the tradition's default icon, or null.
  final String? iconKey;

  final FastingRowPlacement placement;

  /// Replaces the computed period name in the day-panel row ("Great Lent" →
  /// "Fasting"), or null to keep the calculated one. Trimmed-empty is stored
  /// as null so a cleared field never shows as a blank title.
  final String? titleOverride;

  /// Extra markdown line under the row's regime, or null. Rendered by the
  /// same clamped `MarkdownInlineText` path event descriptions use, so it
  /// inherits their rules (money disabled, no tap recognizers).
  final String? description;

  const FastingTraditionStyle({
    this.style = FastingDisplayStyle.tint,
    this.colorValue,
    this.iconKey,
    this.placement = FastingRowPlacement.afterHolidays,
    this.titleOverride,
    this.description,
  });

  /// The effective colour: the user's override when set, else [fallback].
  Color colorOr(Color fallback) =>
      colorValue == null ? fallback : Color(colorValue!);

  int get priority => placement.priority;

  FastingTraditionStyle copyWith({
    FastingDisplayStyle? style,
    int? colorValue,
    String? iconKey,
    FastingRowPlacement? placement,
    String? titleOverride,
    String? description,
    bool clearColor = false,
    bool clearIcon = false,
  }) {
    // Text fields normalize instead of taking clear flags: an edit that
    // empties the field *is* the clear, and the caller should not have to
    // notice the difference.
    String? normalize(String? next, String? current) {
      final value = next ?? current;
      if (value == null) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return FastingTraditionStyle(
      style: style ?? this.style,
      colorValue: clearColor ? null : (colorValue ?? this.colorValue),
      iconKey: clearIcon ? null : (iconKey ?? this.iconKey),
      placement: placement ?? this.placement,
      titleOverride: normalize(titleOverride, this.titleOverride),
      description: normalize(description, this.description),
    );
  }

  /// JSON object; null/default-only fields are omitted to keep the stored
  /// value small.
  Map<String, Object?> toJson() => {
    'style': style.name,
    'placement': placement.name,
    if (colorValue != null) 'color': colorValue,
    if (iconKey != null) 'icon': iconKey,
    if (titleOverride != null) 'title': titleOverride,
    if (description != null) 'description': description,
  };

  /// Every field degrades to its default independently, so a partially
  /// corrupt record still yields a usable style instead of throwing.
  static FastingTraditionStyle fromJson(
    Map<String, Object?> json, {
    FastingDisplayStyle? fallbackStyle,
  }) {
    String? text(Object? value) {
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final styleName = json['style'];
    return FastingTraditionStyle(
      style: styleName is String
          ? FastingDisplayStyle.fromName(styleName)
          : (fallbackStyle ?? FastingDisplayStyle.tint),
      colorValue: json['color'] is int ? json['color'] as int : null,
      iconKey: text(json['icon']),
      placement: FastingRowPlacement.fromName(
        json['placement'] is String ? json['placement'] as String : null,
      ),
      titleOverride: text(json['title']),
      description: text(json['description']),
    );
  }

  /// Reads the retired `style|argb|iconKey|placement` record. Kept so an
  /// install written before free-text fields forced the move to JSON does
  /// not lose its look.
  static FastingTraditionStyle decodeLegacy(String raw) {
    final parts = raw.split('|');
    String at(int i) => i < parts.length ? parts[i].trim() : '';
    return FastingTraditionStyle(
      style: FastingDisplayStyle.fromName(at(0)),
      colorValue: int.tryParse(at(1)),
      iconKey: at(2).isEmpty ? null : at(2),
      placement: FastingRowPlacement.fromName(at(3)),
    );
  }

  @override
  List<Object?> get props => [
    style,
    colorValue,
    iconKey,
    placement,
    titleOverride,
    description,
  ];
}

/// The whole fasting look & feel: one [FastingTraditionStyle] per tradition.
///
/// Traditions absent from [byTradition] use the default style, so enabling a
/// tradition never requires writing an appearance record first.
class FastingAppearance extends Equatable {
  final Map<FastingTradition, FastingTraditionStyle> byTradition;

  const FastingAppearance({this.byTradition = const {}});

  FastingTraditionStyle styleFor(FastingTradition tradition) =>
      byTradition[tradition] ?? const FastingTraditionStyle();

  FastingAppearance withStyle(
    FastingTradition tradition,
    FastingTraditionStyle style,
  ) {
    return FastingAppearance(
      byTradition: {...byTradition, tradition: style},
    );
  }

  /// JSON object keyed by [FastingTradition.name].
  ///
  /// JSON rather than a delimited record because the styles carry free text
  /// (title override, description) that can contain any separator a compact
  /// encoding would pick — escaping by hand is exactly the kind of thing
  /// that silently corrupts one user's data.
  String encode() => jsonEncode({
    for (final entry in byTradition.entries)
      entry.key.name: entry.value.toJson(),
  });

  /// Decodes [encode]'s output — or, transparently, the retired
  /// `tradition:style|argb|icon|placement;…` form. Records for traditions
  /// this build does not know are dropped, and anything unparseable yields
  /// defaults rather than throwing: a corrupt settings row must never keep
  /// the calendar from opening.
  ///
  /// [fallbackStyle] seeds records that predate per-tradition styling (the
  /// retired single global style setting).
  static FastingAppearance decode(
    String? raw, {
    FastingDisplayStyle? fallbackStyle,
  }) {
    final byTradition = <FastingTradition, FastingTraditionStyle>{};
    final trimmed = raw?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      if (trimmed.startsWith('{')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map) {
            decoded.forEach((key, value) {
              final tradition = FastingTradition.fromName(key?.toString());
              if (tradition == null || value is! Map) return;
              byTradition[tradition] = FastingTraditionStyle.fromJson(
                value.map((k, v) => MapEntry(k.toString(), v)),
                fallbackStyle: fallbackStyle,
              );
            });
          }
        } on FormatException {
          // Fall through to the empty/fallback path below.
        }
      } else {
        for (final record in trimmed.split(';')) {
          final split = record.indexOf(':');
          if (split <= 0) continue;
          final tradition = FastingTradition.fromName(
            record.substring(0, split).trim(),
          );
          if (tradition == null) continue;
          byTradition[tradition] = FastingTraditionStyle.decodeLegacy(
            record.substring(split + 1),
          );
        }
      }
    }
    if (byTradition.isEmpty && fallbackStyle != null) {
      // Migration from the single global style: every tradition inherits it.
      for (final tradition in FastingTradition.values) {
        byTradition[tradition] = FastingTraditionStyle(style: fallbackStyle);
      }
    }
    return FastingAppearance(byTradition: byTradition);
  }

  @override
  List<Object?> get props => [byTradition];
}
