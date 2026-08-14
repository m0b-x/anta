import 'package:equatable/equatable.dart';

import '../constants/json_keys.dart';

enum CounterScope { global, perNote }

class Counter extends Equatable {
  final String id;
  final String name;
  final int startValue;
  final int step;
  final CounterScope scope;
  final bool isPinned;
  final DateTime createdAt;

  const Counter({
    required this.id,
    required this.name,
    this.startValue = 1,
    this.step = 1,
    this.scope = CounterScope.global,
    this.isPinned = false,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    JsonKeys.id: id,
    JsonKeys.name: name,
    JsonKeys.counterStartValue: startValue,
    JsonKeys.counterStep: step,
    JsonKeys.counterScope: scope.name,
    JsonKeys.counterIsPinned: isPinned,
    JsonKeys.createdAt: createdAt.toIso8601String(),
  };

  factory Counter.fromJson(Map<String, dynamic> json) {
    return Counter(
      id: json[JsonKeys.id] as String,
      name: json[JsonKeys.name] as String,
      startValue: json[JsonKeys.counterStartValue] as int? ?? 1,
      step: json[JsonKeys.counterStep] as int? ?? 1,
      scope: CounterScope.values.firstWhere(
        (s) => s.name == (json[JsonKeys.counterScope] as String? ?? 'global'),
        orElse: () => CounterScope.global,
      ),
      isPinned: json[JsonKeys.counterIsPinned] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json[JsonKeys.createdAt] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Counter copyWith({
    String? id,
    String? name,
    int? startValue,
    int? step,
    CounterScope? scope,
    bool? isPinned,
    DateTime? createdAt,
  }) {
    return Counter(
      id: id ?? this.id,
      name: name ?? this.name,
      startValue: startValue ?? this.startValue,
      step: step ?? this.step,
      scope: scope ?? this.scope,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    startValue,
    step,
    scope,
    isPinned,
    createdAt,
  ];
}
